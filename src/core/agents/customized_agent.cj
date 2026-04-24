package metis.core.agents

import magic.dsl.*
import magic.prelude.*
import magic.log.LogUtils
import magic.config.Config
import magic.tool.{AgentAsTool, SubAgentMode}
import magic.prompt.Template

import metis.core.tools.*
import metis.core.config.CliConfig
import metis.core.model.CliModelManager
import metis.core.agents.subagents.*
import metis.core.agents.common.*
import metis.utils.loadMarkdown

import std.fs.{Path, exists, canonicalize}

private let SYSTEM_PROMPT_TEMPLATE = """
<file-content path="{AGENT_DIR}/AGENT.md">
{CUSTOMIZED_PROMPT}
</file-content>

# RECURSIVE DOCUMENTATION READING
- You should NEVER read {AGENT_DIR}/AGENT.md again
- When reading a file, pay attention to any **cross-references** or **further reading suggestions** within the content (e.g., "If you want to optimize tiling, read `./advanced_tiling.md`", "Refer to `./memory_coalescing.md` for details", "For more information on atomics, check `./atomic_operations.md`"), you should decide whether to read references further.
- If you decide to read any referenced file (md file or other files), you **must** use the `loadReferenceFile` tool to read it. Example: File `./a/b/memory_model.md` is referenced by the markdown file `{AGENT_DIR}/foo.md`, use `loadReferenceFile("{AGENT_DIR}/foo.md", "./a/b/memory_model.md")`
- NOTE THAT: The root file described the above content is `{AGENT_DIR}/AGENT.md`, which should not be read again.
- Always track which documents you've read to avoid redundant reads
"""

@agent[
    model: CliModelManager.model,
    temperature: CliConfig.temperature,
    executor: "tool-loop:1000"
]
public class CustomAgent {
    private let agentDir: Path

    public init(agentDir: Path) {
        this.agentDir = agentDir
        let (metadata, content) = loadMarkdown(agentDir.join("AGENT.md"))

        this.systemPrompt = SYSTEM_PROMPT_TEMPLATE.format([
            ("CUSTOMIZED_PROMPT", content),
            ("AGENT_DIR", agentDir.toString())
        ])
        this.name = metadata.get("name") ?? "Customized Agent"
        this.description = metadata.get("description") ?? "Customized Agent"

        for (tool in (metadata.get("tools") ?? "").split(",")) {
            match (tool.trimAscii()) {
                case "listDirectory" => this.toolManager.addTool(listDirectory)
                case "fileRead" => this.toolManager.addTool(fileRead)
                case "fileCreate" => this.toolManager.addTool(fileCreate)
                case "fileWrite" => this.toolManager.addTool(fileWrite)
                case "fileEdit" => this.toolManager.addTool(fileEdit)
                case "shellExecute" => this.toolManager.addTool(shellExecute)
                case "grepSearch" => this.toolManager.addTool(grepSearch)
                case "globSearch" => this.toolManager.addTool(globSearch)
                case _ => LogUtils.error("Unknown tool: ${tool.trimAscii()}")
            }
        }
    }

    @tool[
        description: "Loads the content of a markdown file referenced by a relative path from the markdown file.",
        parameters: {
            mdFilePath: "The absolute path of the markdown file that contains the reference.",
            reference: "The relative path to the reference file from the markdown file."
        }
    ]
    func loadReferenceFile(mdFilePath: String, reference: String): String {
        let referencePath = Path(mdFilePath).parent.join(reference)
        if (!exists(referencePath)) {
            return "Error: Reference file not found at ${referencePath.toString()}"
        }
        return fileRead(canonicalize(referencePath).toString(), None, None)
    }
}
