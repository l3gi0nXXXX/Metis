package metis.cliapp

import magic.core.agent.*
import magic.log.LogUtils
import magic.core.message.{Message, MessageList, ChatRound}

import metis.io.*
import metis.core.config.CliConfig
import metis.core.model.CliModelManager
import metis.core.config.CliSettingManager
import metis.core.skills.SkillsPrompt
import metis.core.skills.tryHandleSkillsCommand
import metis.core.mcp.MCPConfigManager
import metis.core.conversation.ConversationManager
import metis.core.commands.CustomCommandManager
import metis.gateway.runtime.{gatewayCliShouldPrintRuntimeRequiredHint, gatewayInvokeCliAgent, runGatewayDashboardCli}
import metis.gateway.core.{GatewaySessionStore, gatewayMigrateLegacyGatewaySessionsIfNeeded, gatewayPersistedSessionsRootForUser}
import metis.utils.ShellUtils
import metis.telemetry.DataCollector
import metis.io.CompletionListUtils

import std.collection.{ArrayList, enumerate, filter, map, collectArray}
import std.fs.{exists, File, FSException, Path, Directory}
import std.sync.{AtomicOptionReference, AtomicBool}

/**
 * Main input processing function - determines input type and routes accordingly
 */
func processInput(app: CliApp, input: String): Bool {
    if (input.startsWith("!")) {
        // Shell command - remove "!" and execute
        executeShellCommand(input[1..], app)
        return true  // Continue running
    }
    // Try to execute as a built-in or customized command
    if (let Some(status) <- executeCommand(input, app)) {
        return status
    }
    // Otherwise, let agent process the input
    try {
        executeAgent(app, input)
    } catch (ex: Exception) {
        let msg = "Execution failure: ${ex.message}"
        PrintUtils.printLine(msg.withColor(AnsiColor.color256(100)))
        LogUtils.error(ex)
    }
    return true  // Continue running
}

//-------------------------------------------------------

/**
 * Execute shell command (input starting with !)
 */
private func executeShellCommand(command: String, app: CliApp): Unit {
    LogUtils.info("Executing shell command: ${command}")
    if (command.trimAscii().isEmpty()) {
        PrintUtils.printLine("Shell Command: No command provided after '!'.")
        return
    }
    //let items = command.split(" ")  // Simple split by space, does not handle quotes
    //let args = if (items.size > 1) { items[1..] } else { Array<String>() }
    InputUtils.lockTerminalInput()
    InputUtils.exitRawMode()
    try {
        let exitCode = ShellUtils.executeInteractive([command], workDir: CliConfig.cwd)
        LogUtils.info("Shell command exited with code ${exitCode}")
    } finally {
        InputUtils.enterRawMode()
        InputUtils.unlockTerminalInput()
    }
}

//-------------------------------------------------------

/**
 * Execute built-in commands and return whether to continue running
 */
private func executeCommand(input: String, app: CliApp): Option<Bool> {
    match (input) {
        case "/exit" | "exit" =>
            PrintUtils.printExitMessage()
            return false  // Signal to exit main loop

        case "/help" | "help" =>
            CustomCommandManager.printBuiltinCommands()
            return true

        case "/clear" | "clear" =>
            app.conversationManager.clearConversation()
            PrintUtils.clearScreen()
            PrintUtils.printLogo()
            return true

        case "/compact" | "compact" =>
            app.conversationManager.compact(manual: true)
            return true

        case "/memory" | "memory" =>
            let memoryPath = CliConfig.cwd.join("MEMORY.md")
            let memoryAltPath = CliConfig.cwd.join("memory.md")
            let memoryDir = CliConfig.cwd.join("memory")
            if (exists(memoryPath)) {
                PrintUtils.printLine("🧠 Current MEMORY.md content:")
                PrintUtils.printLine(String.fromUtf8(File.readFrom(memoryPath)))
            } else if (exists(memoryAltPath)) {
                PrintUtils.printLine("🧠 Current memory.md content:")
                PrintUtils.printLine(String.fromUtf8(File.readFrom(memoryAltPath)))
            } else if (exists(memoryDir)) {
                PrintUtils.printLine("🧠 No MEMORY.md found, but memory/ directory exists:")
                for (entry in Directory.readFrom(memoryDir)) {
                    PrintUtils.printLine(" - ${entry.name}")
                }
            } else {
                PrintUtils.printLine("🧠 No MEMORY.md or memory/ directory found in current workspace")
                PrintUtils.printLine("Use the memory tools or clear the conversation to start creating memory files.")
            }
            return true

        case _input where isMemoryCommandLine(_input) =>
            handleMemoryLine(_input)
            return true

        case _input where _input.trimAscii().startsWith("/dreaming") || _input.trimAscii().startsWith("dreaming ") || _input.trimAscii() == "dreaming" =>
            let forwarded = if (_input.trimAscii().startsWith("/dreaming")) {
                "/memory " + _input.trimAscii()[1..]
            } else {
                "/memory " + _input.trimAscii()
            }
            handleMemoryLine(forwarded)
            return true

        case "/init" | "init" =>
            initAgentsFile()
            return true

        case "/status" | "status" =>
            PrintUtils.printLine("Status scope: CLI chat token/session usage. This is not gateway runtime status; use `metis gateway status` or `/dashboard` for gateway health.")
            app.tokenStatusManager.printStatus()
            return true

        case _input where isModelsCommandLine(_input) =>
            handleModelsCommandLine(app, _input)
            return true

        case _input where isDashboardCommandLine(_input) =>
            openDashboard(_input)
            return true

        case _input where _input.trimAscii().startsWith("/skills ") || _input.trimAscii().startsWith("skills ") =>
            if (let Some(out) <- tryHandleSkillsCommand(_input)) {
                PrintUtils.printLine(out)
            }
            return true

        case _input where isMetisCommandLine(_input) =>
            handleMetisLine(app, _input)
            return true

        case _input where isGatewayPluginCommandLine(_input) =>
            handleGatewayPluginLine(_input)
            return true

        case _input where isGatewaySessionsCommandLine(_input) =>
            handleGatewaySessionsLine(_input)
            return true

        case _input where isGatewaySubagentsCommandLine(_input) =>
            handleGatewaySubagentsLine(_input)
            return true

        case _input where isGatewayCronCommandLine(_input) =>
            handleGatewayCronLine(_input)
            return true

        case _input where isGatewayChannelCommandLine(_input) =>
            handleGatewayChannelLine(_input)
            return true

       case _input where _input.startsWith("/mcp") =>
            app.mcpManager.handleCommand(input.split(" "), app.agent)
            return true

        case _input where _input.startsWith("/conversation") =>
            app.conversationManager.handleCommand(input.split(" "))
            return true

        case _input where _input.startsWith("/cmd") =>
            app.customCommandManager.handleCommand(input)
            return true

        case "/agents" =>
            app.customAgentManager.listAgents()
            return true

        // Handle direct /<command> ...
        case _input where _input.startsWith("/") =>
            // Parse command name + args (supports both `/weather Shanghai` and `/weather`)
            if (let Some(pivot) <- _input.indexOf(b' ')) {
                let cmdName = _input[1..pivot].trimAscii()
                let args = _input[pivot+1..].trimAscii()

                // Slash skill command: explicit skill trigger, skip intent classification.
                if (SkillsPrompt.hasSkillName(cmdName)) {
                    let question = if (args.isEmpty()) { cmdName } else { args }
                    LogUtils.info("Skills: slash command matched '/${cmdName}', forcing skill execution")
                    executeAgentWithForcedSkill(app, question, Some(cmdName))
                    return true
                }

                if (let Some(command) <- app.customCommandManager.getCommand(cmdName)) {
                    let question = app.customCommandManager.handleCustomCommand(command, args)
                    LogUtils.debug("Handle custom command '${cmdName}' with args '${args}'")
                    LogUtils.debug("   Question: ${question}")
                    executeAgent(app, question)
                } else {
                    PrintUtils.printLine("💥 Command '${cmdName}' not found. Use '/cmd list' to see available commands.")
                }
                return true
            } else {
                let cmdName = _input[1..].trimAscii()
                if (!cmdName.isEmpty() && SkillsPrompt.hasSkillName(cmdName)) {
                    LogUtils.info("Skills: slash command matched '/${cmdName}', forcing skill execution")
                    executeAgentWithForcedSkill(app, cmdName, Some(cmdName))
                    return true
                }
                return None
            }

        case _ => // Not an available command
            return None
    }
}

//-------------------------------------------------------

private func isDashboardCommandLine(raw: String): Bool {
    let t = raw.trimAscii().toAsciiLower()
    t == "/dashboard" || t == "dashboard" || t.startsWith("/dashboard ") || t.startsWith("dashboard ")
}

private func openDashboard(raw: String): Unit {
    let tokens = raw.trimAscii().split(" ") |>
        filter { x => !x.trimAscii().isEmpty() } |>
        map { x => x.trimAscii() } |>
        collectArray
    let args = ArrayList<String>()
    var i: Int64 = 1
    while (i < tokens.size) {
        args.add(tokens[i])
        i += 1
    }
    let _ = runGatewayDashboardCli(args.toArray())
}

//-------------------------------------------------------

private func executeAgent(app: CliApp, input: String): Unit {
    executeAgentWithForcedSkill(app, input, None)
}

private func executeAgentWithForcedSkill(app: CliApp, input: String, forcedSkillName: Option<String>): Unit {
    let (ok, needsRuntimeHint) = executeAgentViaGateway(input, forcedSkillName: forcedSkillName)
    if (ok) {
        return
    }
    if (needsRuntimeHint) {
        PrintUtils.printLine(
            "The unified Gateway main runtime is required for CLI chat. Start it with `metis gateway run`, or use `metis agent --local --message \"...\"` for explicit embedded mode."
        )
    }
}

private func executeAgentViaGateway(input: String, forcedSkillName!: Option<String> = None<String>): (Bool, Bool) {
    let prompt = match (forcedSkillName) {
        case Some(skillName) =>
            let normalized = skillName.trimAscii()
            if (normalized.isEmpty()) {
                input
            } else if (input.trimAscii().isEmpty()) {
                "/${normalized}"
            } else {
                "/${normalized} ${input.trimAscii()}"
            }
        case None => input
    }
    let (ok, answer, err) = gatewayInvokeCliAgent(prompt, sessionKey: "main", channel: "cli")
    if (!ok) {
        LogUtils.error("Gateway agent invoke failed: ${err}")
        PrintUtils.printLine("Gateway agent failed: ${err}")
        return (false, gatewayCliShouldPrintRuntimeRequiredHint(err))
    }
    PrintUtils.printLine("")
    PrintUtils.printLine(PrintUtils.renderAssistantResponseBox(answer))
    PrintUtils.printLine("")
    PrintUtils.printLine("")
    (true, false)
}

private func executeAgentEmbeddedWithForcedSkill(app: CliApp, input: String, forcedSkillName: Option<String>): Unit {
    LogUtils.debug("Handle user input `${input}`")
    // Each time we execute an agent task, we need to reset the sub-agent indent
    PrintUtils.resetSubAgent()

    // Parse agent name and question to get the agent to use
    let (agent, question) = parseAgentAndQuestion(app, input.trimAscii())
    let isSubagent = agent.name != app.agent.name

    // Try all available models in sequence.
    // If a skill specifies `model` (+ apikey), try it first; otherwise use global models.
    var allModels = CliModelManager.getAllModels()

    // Skill-driven model selection + UI hints (optional per-skill model overrides).
    let skillsEnabled = CliSettingManager.readSkillsEnabled()
    let decision = SkillsPrompt.decideForInput(question, forcedSkillName)
    let selectedSkillNameOpt = decision.selectedSkillName
    let enabledSelectedSkillNameOpt: Option<String> = match (selectedSkillNameOpt) {
        case Some(skillName) => if (decision.selectedSkillEnabled) { Some(skillName) } else { None }
        case None => None
    }
    var effectiveQuestion = question
    // Slash command forced skill path: keep behavior deterministic.
    if (let Some(forcedSkill) <- forcedSkillName) {
        let fs = forcedSkill.trimAscii()
        if (!fs.isEmpty()) {
            effectiveQuestion =
                "【系统附加约束】用户已显式指定技能 /${fs}。" +
                "请严格按该技能处理当前问题，不要切换到其他技能或其他工具路径；" +
                "若信息不足，请按该技能的规则给出澄清或失败说明。\n\n用户问题：${question}"
        }
    }
    if (let Some(skillName) <- selectedSkillNameOpt) {
        if (!SkillsPrompt.isSkillEnabledByName(skillName)) {
            effectiveQuestion =
                "【系统附加约束】已匹配到 skill '${skillName}'，但该 skill 当前在 metis.json 中被禁用。" +
                "本轮回答禁止调用任何工具（包括 weather），请直接基于通用模型知识回答用户问题；" +
                "不要给出“去启用配置”的建议。\n\n用户问题：${question}"
        }
    }
    if (skillsEnabled) {
        match (selectedSkillNameOpt) {
            case Some(skillName) =>
                let enabled = SkillsPrompt.isSkillEnabledByName(skillName)
                if (enabled) {
                    PrintUtils.printLine("匹配到 skill：${skillName}（enabled=true）".withColor(AnsiColor.WHITE))
                } else {
                    PrintUtils.printLine(
                        "匹配到 skill：${skillName}（enabled=false）。如需使能，请修改 metis.json 中对应的 skills 配置。"
                            .withColor(AnsiColor.WHITE)
                    )
                }
            case None => ()
        }
    }
    match (selectedSkillNameOpt) {
        case Some(skillName) =>
            let enabled = SkillsPrompt.isSkillEnabledByName(skillName)
            LogUtils.info("Skills: matched skill='${skillName}' for input (enabled=${enabled})")
        case None =>
            LogUtils.info("Skills: no matched skill for input; no skill logic will be injected")
    }

    // Skills prompt uses metadata only; skill bodies should be read on demand.
    let availableSkillsMeta = if (skillsEnabled) {
        SkillsPrompt.buildAvailableSkillsMetadataForPrompt()
    } else {
        ""
    }
    if (!availableSkillsMeta.trimAscii().isEmpty()) {
        effectiveQuestion =
            "【技能元信息】\n" + availableSkillsMeta + "\n\n" +
            "【技能执行规则】先判断是否需要技能；仅当意图明确时读取并遵循对应 SKILL.md；不明确返回 none。\n\n" +
            "用户问题：\n" + effectiveQuestion
    }
    try {
        for ((idx, currModel) in enumerate(allModels)) {
            try {
            let revertSkillEnv = match (enabledSelectedSkillNameOpt) {
                case Some(skillName) => SkillsPrompt.applyRuntimeEnvOverridesForSkill(skillName)
                case None => { => () }
            }
            // Always switch agent model for each attempt.
            if (idx == 0) {
                LogUtils.debug("Use model: ${currModel.fullName}")
            } else {
                PrintUtils.printLine("Model Fallback: switch to: ${currModel.fullName}")
                LogUtils.debug("Switch model: ${currModel.fullName}")
            }
            agent.model = currModel

            // Execute with the current model
            try {
                let asyncResponse = if (isSubagent) {
                    //  Sub-agent process the question without conversations
                    agent.asyncChat(AgentRequest(effectiveQuestion))
                } else {
                    agent.asyncChat(
                        AgentRequest(effectiveQuestion, conversation: app.conversationManager.conversation)
                    )
                }
                // Start cancellation checker
                let cancelChecker = CancelChecker(app, asyncResponse)
                cancelChecker.start()
                asyncResponse.addFinishFn({ _: Bool =>
                    cancelChecker.stop()
                })
                // Unified handling for all cases (Success, Cancelled, Failed)
                handleAgentResponse(app, question, asyncResponse, cancelChecker: cancelChecker, isSubagent: isSubagent)
                cancelChecker.waitUntilStop()
                CliModelManager.lastAvailableModel = currModel
                return // Success, exit retry loop
            } finally {
                revertSkillEnv()
            }
        } catch (ex: Exception) {
            if (idx == allModels.size - 1) { // All models are tried
                if (!isSubagent) {
                    saveIncompleteChatRound(app, question, ex.message)
                }
                throw ex
            } else if (CliModelManager.shouldFallback(ex)) {
                LogUtils.info("Model ${currModel.fullName} failed, trying fallback")
            } else {
                throw ex
            }
        }
        }
    } finally {
    }
}

/**
 * Save an incomplete chat round when conversation is cancelled or failed
 */
private func saveIncompleteChatRound(
    app: CliApp,
    question: String,
    answer: String): Unit {
    try {
        let chatRound = ChatRound(
            Message.user(question),
            Message.assistant(answer),
            MessageList() // Empty steps to avoid concurrent access
        )
        app.conversationManager.conversation.addChatRound(chatRound)
        appendCliMainSessionTranscript(question, answer)
        LogUtils.debug("Saved incomplete chat round: question='${question}', answer='${answer}'")
    } catch (ex: Exception) {
        LogUtils.error("Failed to save incomplete chat round: ${ex.message}")
    }
}

private func appendCliMainSessionTranscript(userText: String, assistantText: String): Unit {
    try {
        let gw = CliSettingManager.readGatewaySettings()
        let root = gatewayPersistedSessionsRootForUser(gw)
        gatewayMigrateLegacyGatewaySessionsIfNeeded(root)
        let store = GatewaySessionStore(root, enabled: true, agentId: gw.session.agentId)
        let sessionKey = "cli:main:main"
        if (!userText.trimAscii().isEmpty()) {
            store.appendUser(sessionKey, userText)
        }
        if (!assistantText.trimAscii().isEmpty()) {
            store.appendAssistant(sessionKey, assistantText)
        }
    } catch (ex: Exception) {
        LogUtils.debug("appendCliMainSessionTranscript failed: ${ex.message}")
    }
}

/**
 * Parse the input string to extract the agent name and the question.
 * Case 1: @<agent-name> ...., return agent and question
 * Case 2: no agent name, return None for agent name
 */
private func parseAgentAndQuestion(app: CliApp, input: String): (Agent, String) {
    if (!input.startsWith("@")) {
        return (app.agent, input) // No agent name, return default agent
    }
    if (let Some(pivot) <- input.indexOf(b' ')) {
        let name = input[1..pivot] // Remove the leading '@'
        let args = input[pivot..].trimAscii()

        if (let Some(subAgent) <- app.customAgentManager.getAgent(name)) {
            return (subAgent, args)
        }
    }
    return (app.agent, input) // No sub-agent found, return default agent
}
/**
 * Handle the agent response, print the response and update the conversation
 */
private func handleAgentResponse(
    app: CliApp,
    input: String,
    response: AsyncAgentResponse,
    cancelChecker!: CancelChecker,
    isSubagent!: Bool): Unit {
    let streamed = streamAgentResponse(app, response)
    let content = response.content
    match (response.status) {
        case AgentResponseStatus.Success =>
            // Check if cancellation occurred
            if (!streamed && !content.isEmpty()) {
                PrintUtils.printAgentResponse(response)
            }
            if (!isSubagent) {
                app.conversationManager.conversation.addChatRound(response.execution.chatRound)
                appendCliMainSessionTranscript(input, content)
                app.conversationManager.compact()
                spawn {
                    DataCollector.collectChatRound(response.execution.chatRound)
                }
            }
        case AgentResponseStatus.Cancelled =>
            if (!isSubagent) {
                // After response.content is accessed, finished = true, execution thread has stopped
                // Set answer manually for cancelled case, then try to access chatRound to get steps
                try {
                    // Set answer manually since it's not set in cancelled case
                    response.execution.setAnswer(content)
                    app.conversationManager.conversation.addChatRound(response.execution.chatRound)
                    appendCliMainSessionTranscript(input, content)
                    LogUtils.debug("Saved cancelled chat round with steps")
                } catch (ex: Exception) {
                    // Fallback if chatRound access fails
                    saveIncompleteChatRound(app, input, content)
                    LogUtils.debug("Failed to access chatRound for cancelled case, used fallback: ${ex.message}")
                }
            }
        case AgentResponseStatus.Failed =>
            if (!streamed) {
                app.stopThinkIndicator()
            }
            PrintUtils.printLine(response.content.withColor(AnsiColor.color256(240)))
            if (!isSubagent) {
                try {
                    response.execution.setAnswer(content)
                    app.conversationManager.conversation.addChatRound(response.execution.chatRound)
                    appendCliMainSessionTranscript(input, content)
                    LogUtils.debug("Saved failed chat round with steps")
                } catch (ex: Exception) {
                    saveIncompleteChatRound(app, input, content)
                    LogUtils.debug("Failed to access chatRound for failed case, used fallback: ${ex.message}")
                }
            }
    }
}

private func streamAgentResponse(app: CliApp, response: AsyncAgentResponse): Bool {
    var hasStreamed = false
    try {
        for (_chunk in response) {
            if (!hasStreamed) {
                hasStreamed = true
                app.stopThinkIndicator()
            }
        }
    } catch (_ex: Exception) {
        // Response status/content will be handled by the caller after iteration stops.
    } finally {
        if (hasStreamed) {
            PrintUtils.printAgentResponse(response)
        }
    }
    return hasStreamed
}
