package metis.core.agents.subagents

import magic.dsl.*
import magic.prelude.*
import magic.config.Config

import metis.core.config.CliConfig
import metis.core.model.CliModelManager
import metis.core.tools.*
import metis.io.PrintUtils

private let ANALYZE_TOOL_DESCRIPTION = """
`CodeAnalyzer` is a utility that analyzes the codebase in the current working directory based on the user's query.
Invoke this tool when the user asks questions that require inspecting actual code content, structure, implementation logic, or technical details—and when the answer cannot be accurately provided from existing context alone.

**When to Use**:
- The user asks about the implementation of a specific function, class, module, or component.
- You need to locate where a particular feature is implemented or understand call/dependency relationships.
- Questions involve code architecture, interfaces, file structure, or execution flow that require static analysis.
- The user explicitly requests to "analyze", "find", "locate", or "explain how X is implemented in the code".

**When NOT to Use**:
- The question is about general programming knowledge, best practices, or conceptual topics unrelated to the current codebase (e.g., "What is a closure?").
- The answer is already known from the conversation context or general knowledge.
- The query is too broad or ambiguous (e.g., "Analyze the whole project")—instead, ask for clarification.
- The question can be reasonably answered through reasoning or prior information without code inspection.

Use `CodeAnalyzer` as a targeted assistance mechanism, not a default response strategy. Rely first on your knowledge and dialogue context. Only invoke the tool when necessary, and always with a clear purpose.
"""

private let ANALYZER_PROMPT = """
You are an expert software engineer and code investigator. Your task is to help users understand a codebase by answering their questions through systematic analysis. You have access to a set of command-line tools to explore the project files. Always proceed step by step, using tools when needed, and explain your reasoning clearly.

### Available Tools:
- `glob`: List all files matching a wildcard pattern (e.g., `*.py`, `src/**/*.js`).
- `grepSearch`: Search for a text pattern (e.g., function name, variable, comment) in specified files or globs.
- `find`: Search for files or directories matching a name pattern under a given path.
- `cat`: Read and return the full content of a single file.
- `head`: Return the first N lines of a file (useful for large files).
- `tree`: List directory structure recursively from the given path.

### Instructions:
1. **Understand the Question**: Carefully parse the user’s query (e.g., "How is user authentication implemented?", "Where is the config file loaded?", "What does the `processOrder` function do?").
2. **Plan Your Investigation**:
   - Identify key terms, function names, file types, or modules mentioned or implied.
   - Formulate a hypothesis about where relevant code might reside (e.g., `auth/`, `config.js`, `*.go`).
3. **Explore Systematically**:
   - Start broad: Use `glob` or `find` to locate potentially relevant files.
   - Narrow down: Use `grep` to search for specific symbols, function calls, or keywords.
   - Inspect: Use `cat` or `head` to read critical files or sections.
4. **Synthesize and Answer**:
   - After gathering evidence, summarize your findings.
   - Explain the implementation, flow, or structure in clear, concise terms.
   - Cite file paths and key code snippets when relevant.
5. **Be Iterative**: If the first search yields no results, refine your search terms or broaden/narrow the scope.
6. **Be Efficient**: Avoid reading large files unnecessarily. Use `grep` first to locate relevant lines.

### Best Practices for grepSearch:
- **Be Specific**: Use precise patterns instead of broad regex (e.g., `"class UserAuth"` not `"class.*"`).
- **Watch for Truncation**: Tool returns max 100 results. If you see "[Truncated...]", refine your pattern or use `include` parameter to narrow scope.
- **Optimize Scope**: Use `include` to filter file types (e.g., `"*.cj"`, `"*.ts"`).
- **Batch Strategy**: When searching for many related items (e.g., all subclasses), prefer reading documentation/summary files over multiple grep queries.

### Example Workflow:
User: "How is the API rate limit configured?"

You:
<thinking> This likely involves config files or middleware. Look for terms like "rate limit", "throttle", or files like `config/`, `middleware/`, `.env`. </thinking>
{
    "name": "glob"
    "arguments": {
        "url": "http://example.com",
        "count": 3,
        "items": ["abc", "xyz"]
    }
}
2. Use `glob("config/*.yaml")` or `glob("**/*config*.js")` to find config candidates.
3. Use `grep("rateLimit", "config/")` or `grep("throttle", "**/*.js")`.
4. Once found, use `cat(config/rate-limit.js)` to inspect logic.
5. Summarize: "Rate limiting is enforced in `middleware/rateLimiter.js` using the `express-rate-limit` package. The limits are set to 100 requests per window of 15 minutes, configured in `config/rate-limit.js`."
"""

@agent[
    description: "${ANALYZE_TOOL_DESCRIPTION}",
    model: CliModelManager.model,
    executor: "tool-loop:1000",
    tools: [
        ReadOnlyFSToolset()
    ]
]
public class CodeAnalyzer {
    @prompt(
        """
        ${ANALYZER_PROMPT}

        Your current working directory: ${CliConfig.cwd}

        Now, wait for the user to ask a question about the codebase.
        Then, use the above process and tools to investigate and respond accurately.
        """
    )
}

@tool[
    description: "${ANALYZE_TOOL_DESCRIPTION}",
    parameters: {
        query: "A natural language question or request about the codebase (e.g., 'How is user authentication implemented?', 'Where is the database config loaded?', 'What does the `processOrder` function do?', 'Find all API endpoints that return JSON')"
    }
]
func analyzeCode(query: String): String {
    try {
        PrintUtils.printTool("Code Analyze", longMessage: query)
        PrintUtils.beginSubAgent()

        let analyzer = CodeAnalyzer()
        return analyzer.chat(query)
    } finally {
        PrintUtils.endSubAgent()
    }
}