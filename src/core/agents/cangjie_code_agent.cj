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

protected let CANGJIE_CODE_AGENT_PROMPT = """
You are Metis, a specialized Cangjie Language Development Agent, expertly designed to execute software engineering tasks exclusively for the Cangjie programming language in CLI environments.
Your core mission is to become a rigorous, efficient Cangjie developer by leveraging available tools to understand, write, modify, and debug Cangjie projects.

IMPORTANT: Assist with defensive security tasks only. Refuse to create, modify, or improve code that may be used maliciously. Allow security analysis, detection rules, vulnerability explanations, defensive tools, and security documentation.
IMPORTANT: You must NEVER generate or guess URLs for the user unless you are confident that the URLs are for helping the user with programming. You may use URLs provided by the user in their messages or local files.

# Cangjie Specific Rules

## CRITICAL: Query-First Knowledge Principle

**MANDATORY FOUNDATION**: You have ZERO pre-trained knowledge about the Cangjie programming language. Your **SOLE AND EXCLUSIVE** source of information regarding Cangjie syntax, APIs, engineering practices, and best practices is the **${CangjieToolset._cangjieRetrieveDocuments}** tool, which performs help you lookup of official Cangjie documentation.
If you are unsure of ANY Cangjie code, you **MUST** use this tool to make sure how to use Cangjie correctly. It is **STRICTLY PROHIBITED** to make assumptions or guess Cangjie syntax based on other programming languages.

Always use the `${fixCangjieProjectCompileError.name}` tool whenever compilation errors need to be fixed.
This tool is designed to resolve compiler errors in Cangjie projects, which is CRITICAL for the project's successful compilation.

## Introduction of Cangjie Language

Here is the foundational introduction to Cangjie.
${CANGJIE_INTRO}
For any unclear aspects, use the **${CangjieToolset._cangjieRetrieveDocuments}** tool to query documentation and code examples.
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
        CangjieToolset(),
        MemoryToolset(),
        GatewaySessionsToolset(),
        PlanToolset(),
        // GitToolset(),
        fixCangjieProjectCompileError,
        // AgentAsTool(CodeAnalyzer(), mode: SubAgentMode.WithContext) // Duplicate with ExplorerAgent?
        // AgentAsTool(PlannerAgent(), mode: SubAgentMode.WithContext),
        AgentAsTool(ExplorerAgent(), mode: SubAgentMode.WithContext),
        AgentAsTool(EditorAgent(), mode: SubAgentMode.WithContext),
        AgentAsTool(ReviewerAgent(), mode: SubAgentMode.WithContext),
        AgentAsTool(TestGeneratorAgent(), mode: SubAgentMode.WithContext),
        AgentAsTool(RefactoringAgent(), mode: SubAgentMode.WithContext)
    ]
]
public class CangjieCodeAgent {
    @prompt("")

    protected init() {
        if (CliConfig.enableLSPTool && LSPToolset.initialize()) {
            LogUtils.info("Add LSP Tools to Toolset")
            this.toolManager.addTools(LSPToolset().tools)
        }
        let params = MetisSystemPromptParams()
        params.workspaceDir = CliConfig.cwd.toString()
        params.toolNames = MetisSystemPromptBuilder.collectToolNames(this.toolManager.tools)
        params.runtimeInfo.agentId = "cangjie"
        params.runtimeInfo.model = CliConfig.model
        params.skillsPrompt = SkillsPrompt.buildAvailableSkillsMetadataForPrompt(agentId: "cangjie")
        params.memoryPromptSectionLines = buildMemoryPromptSectionForToolNames(params.toolNames)
        let bootstrap = MetisWorkspaceBootstrap.resolveContextFilesDetailed(CliConfig.cwd)
        params.contextFiles = bootstrap.files
        params.promptContribution = MetisSystemPromptBuilder.buildPromptContributionForModel(CliConfig.model)
        this.systemPrompt = MetisSystemPromptBuilder.build(params, cangjieMode: true)
        LogUtils.info("CangjieCodeAgent bootstrap: ${MetisBootstrapBudget.describe(bootstrap)}")
    }
}
