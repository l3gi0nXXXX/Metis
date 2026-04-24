package metis.app

import magic.core.agent.AgentRequest

import metis.core.agents.subagents.CodeAnalyzer
import metis.core.config.CliConfig
import metis.io.{InputUtils, PrintUtils}

import std.fs.{exists, File}

private const INIT_PROMPT = """
Please analyze the current project directory and generate practical AGENTS.md content for coding agents.

Requirements:
1. Analyze project type, programming languages, frameworks, and tools in depth
2. Identify project structure, important files, and configurations
3. Infer appropriate coding standards and best practices
4. Generate project-specific development guidelines and considerations
5. Include specific guidance for AI assistant behavior and constraints
6. Follow AGENTS.md conventions (clear sections, direct instructions, actionable commands)

Language requirements:
- Detect the primary language used in existing project files, documentation, and comments
- Generate the AGENTS.md content in the same language as the project's primary language
- If unable to determine project language, default to Chinese
- For mixed language projects, prioritize the language used in README files and main documentation

Output format requirements:
- Return the complete AGENTS.md file content directly, no explanatory text
- Use Markdown format
- Include sections such as: Project Overview, Build/Test Commands, Code Style, Repository Conventions, Agent Workflow
- Content should be specific and practical to guide future AI assistance work
- DO NOT create or write any files, only return the content

Please start analyzing the project and return the AGENTS.md content:
"""

func initAgentsFile(): Unit {
    let agent = CodeAnalyzer()
    if (exists(CliConfig.agentsMarkdownPath)) {
        let overwrite = InputUtils.getOptions(
            ["Yes, overwrite AGENTS.md", "No, keep existing AGENTS.md"],
            prompt: "AGENTS.md already exists. Overwrite?"
        )
        if (overwrite != Some(0)) {
            PrintUtils.printLine("Cancelled /init.")
            return
        }
    }

    PrintUtils.printProcedure("AGENTS.md Init", "🔍 Analyzing project structure and generating AGENTS.md...")
    let response = agent.chat(AgentRequest(INIT_PROMPT))

    try {
        File.writeTo(CliConfig.agentsMarkdownPath, response.content.toArray())
        PrintUtils.printProcedure("AGENTS.md Init", "✅ AGENTS.md initialized successfully!")

        let runes = response.content.toRuneArray()
        let preview = if (runes.size > 300) {
            String(runes[0..300]) + "..."
        } else {
            String(runes)
        }
        PrintUtils.printLine("📝 Content preview:")
        PrintUtils.printLine(preview)
        PrintUtils.printLine("\n💡 Use '/memory' to view the full content anytime!")
    } catch (e: Exception) {
        PrintUtils.printProcedureFailure("AGENTS.md Init", failure: "❌ Failed to write AGENTS.md: ${e.message}")
    }
}