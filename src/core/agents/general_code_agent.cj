package metis.core.agents

import magic.dsl.*
import magic.prelude.*
import magic.config.Config
import magic.log.LogUtils
import magic.tool.{AgentAsTool, SubAgentMode}

import metis.core.tools.*
import metis.core.config.CliConfig
import metis.core.model.CliModelManager
import metis.core.agents.subagents.*
import metis.core.agents.common.*
import metis.core.memory.buildMemoryPromptSectionForToolNames
import metis.core.prompting.{MetisBootstrapBudget, MetisSystemPromptParams, MetisSystemPromptBuilder, MetisWorkspaceBootstrap}
import metis.core.skills.SkillsPrompt

protected let GENERAL_CODE_AGENT_PROMPT = """
You are Metis, an interactive CLI Coding Agent, specializing in software engineering tasks.
Your primary goal is to help users safely and efficiently while strictly adhering to the following instructions, using the tools available to you.

IMPORTANT: Assist with defensive security tasks only. Refuse to create, modify, or improve code that may be used maliciously. Allow security analysis, detection rules, vulnerability explanations, defensive tools, and security documentation.
IMPORTANT: You must NEVER generate or guess URLs for the user unless you are confident that the URLs are for helping the user with programming. You may use URLs provided by the user in their messages or local files.
IMPORTANT: For weather / forecast questions, use the **weather** tool (wttr.in via HTTP). Do not use the shell to run curl on behalf of the user unless the weather tool is unavailable or the user explicitly asks for a shell command.
"""

@agent[
    model: CliModelManager.model,
    temperature: CliConfig.temperature,
    executor: "tool-loop:1000",
    tools: [
        LegacyInteropToolset(),
        FSToolset(),
        WeatherToolset(),
        ShellTool(),
        BasicMediaToolset(),
        MemoryToolset(),
        GatewaySessionsToolset(),
        PlanToolset(),
        // GitToolset(),
        // AgentAsTool(CodeAnalyzer(), mode: SubAgentMode.WithContext)
        AgentAsTool(ExplorerAgent(), mode: SubAgentMode.WithContext),
        AgentAsTool(EditorAgent(), mode: SubAgentMode.WithContext),
        AgentAsTool(ReviewerAgent(), mode: SubAgentMode.WithContext),
        AgentAsTool(TestGeneratorAgent(), mode: SubAgentMode.WithContext),
        AgentAsTool(RefactoringAgent(), mode: SubAgentMode.WithContext)
    ]
]
public class GeneralCodeAgent {
    @prompt("")

    protected init() {
        let params = MetisSystemPromptParams()
        params.workspaceDir = CliConfig.cwd.toString()
        params.toolNames = MetisSystemPromptBuilder.collectToolNames(this.toolManager.tools)
        params.runtimeInfo.agentId = "general"
        params.runtimeInfo.model = CliConfig.model
        params.skillsPrompt = SkillsPrompt.buildAvailableSkillsMetadataForPrompt(agentId: "general")
        params.memoryPromptSectionLines = buildMemoryPromptSectionForToolNames(params.toolNames)
        let bootstrap = MetisWorkspaceBootstrap.resolveContextFilesDetailed(CliConfig.cwd)
        params.contextFiles = bootstrap.files
        params.promptContribution = MetisSystemPromptBuilder.buildPromptContributionForModel(CliConfig.model)
        this.systemPrompt = MetisSystemPromptBuilder.build(params, cangjieMode: false)
        LogUtils.info("GeneralCodeAgent bootstrap: ${MetisBootstrapBudget.describe(bootstrap)}")
    }
}
