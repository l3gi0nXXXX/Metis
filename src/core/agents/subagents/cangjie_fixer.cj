package metis.core.agents.subagents

import magic.dsl.*
import magic.prelude.*
import magic.config.Config
import magic.log.LogUtils

import metis.core.tools.*
import metis.core.config.CliConfig
import metis.core.tools.cj_utils.{cjpmBuild, modifyCjpmToml, restoreCjpmToml}
import metis.core.model.CliModelManager
import metis.io.PrintUtils
import metis.core.agents.common.*
import metis.telemetry.DataCollector

import std.fs.{File, Path, OpenMode}

const CANGJIE_FIX_TOOL_NAME = "fixCangjieProjectCompileError"

@agent[
    model: CliModelManager.fastModel ?? CliModelManager.model,
    executor: "naive"
]
class CodeFixSummarizer {
    @prompt(
"""
Summarizes the compilation error fixes in Markdown format after all errors have been resolved.
The summary includes the error description, the fix applied, and optionally example code to document the solution for future reference.
This serves as a knowledge base entry for common Cangjie language issues.

Output: A Markdown-formatted string containing the detailed summary of the compilation errors that were fixed. This should include sections for each error type (The title does not need numbering), the cause, the solution, and code examples showing the incorrect and correct syntax. The content is saved locally for future reference and learning.

Example:

### `enum` cannot be used with `==` or `!=` operators

`enum` types cannot be used with `==` or `!=` operators unless they implement `Equatable`.
`std.deriving.Derive` helps to implement `Equatable` for `enum` types quickly.

Example:

```cangjie
import std.deriving.Derive

@Derive[Equatable]
enum E {
    | A
    | B
}
```

### Fix `match` case expression

The `match` case clause does not require curly braces `{ }`. Using them may cause compile errors such as: `expected '=>' in lambda expression`.

### Incorrect

```cangjie
match (someOption) {
    case None => { foo() }
    case Some(_) => { bar() }
}

```cangjie
match (someOption) {
    case None => foo()
    case Some(_) => bar()
}
```
"""
    )
}

private let FIX_RULES = """
### Cangjie Fix Rules

Here are some valuable error-fixing rules to help you resolve errors.

### `enum` cannot be used with `==` or `!=` operators

`enum` types cannot be used with `==` or `!=` operators unless they implement `Equatable`.
`std.deriving.Derive` helps to implement `Equatable` for `enum` types quickly.

Example:

```cangjie
import std.deriving.Derive

@Derive[Equatable]
enum E {
    | A
    | B
}
```

### Fix `match` case expression

The `match` case clause does not require curly braces `{ }`. Using them may cause compile errors such as: `expected '=>' in lambda expression`.

### Incorrect

```cangjie
match (someOption) {
    case None => { foo() }
    case Some(_) => { bar() }
}

### Correct

```cangjie
match (someOption) {
    case None => foo()
    case Some(_) => bar()
}
```

### Reading Input from Standard Input

There are two ways to read input from standard input in Cangjie:

1. The `readln()` function from the `std.core` package:

```cangjie
public func readln(): String
```

This function returns the input directly as a `String`.

2. The `Console` class method:

```cangjie
class Console {
    public func readln(): ?String
}
```

This method returns an `Option<String>`, which means it may return `None` if there's no input available.

Both approaches read a line from standard input, but they differ in their return types.

### Incorrect

```cangjie
match (readln()) {
    case Some(input) => print("You entered: \${input}")
    case None => print("No input received")
}
```

### Correct

```cangjie
let input = readln()
println(input)
```

### Correct

```cangjie
match (console.readln()) { // Note that `console.readln()` returns an `Option<String>`, so we need to handle the `None` case.
    case Some(input) => foo()
    case None => bar()
}
```
"""

private let COMPILE_ERROR_FIXER_PROMPT = """
You are an expert Cangjie expert tasked with resolving **all compile-time errors** in a Cangjie project.
Your **only objective** is to make the project compile successfully by diagnosing and fixing compile errors—**you must not alter the intended behavior, architecture, or design of the software**.

## Introduction of Cangjie Language

<important>
Cangjie is a new programming language and differs to other languages, NEVER make assumptions or guess Cangjie syntax based on other programming languages.
</important>

Here is the quick introduction to Cangjie.

${CANGJIE_INTRO}

${FIX_RULES}

- "### Cangjie Fix Rules" list rules you can use to fix compile errors.
- For any unclear aspects, use the **${CangjieToolset._cangjieRetrieveDocuments}** tool to query documentation and code examples.

**MANDATORY FOUNDATION**: Cangjie is a new programming language and differs to other languages, so your MUST use tool **${CangjieToolset._cangjieRetrieveDocuments}** to lookup Cangjie syntax, APIs, engineering practices, its best practices, etc.
It is **STRICTLY PROHIBITED** to make assumptions or guess Cangjie syntax based on other programming languages.

## Compile Error Fixing Process

Follow this iterative, disciplined process to fix compile errors:

### Iterative Fix Process

1. **Build the Project**
   Always begin and verify with the `${CangjieToolset._cangjieBuildProject}` tool. Use its output as the **authoritative source** of all compile errors. Never assume the state of the build without calling this tool.

2. **Diagnose Error**
   For each error:
   - Classify it: syntax error, undefined symbol, type mismatch, incorrect API usage, etc.
   - If the fix is clear and you are confident, proceed to editing.
   - Check rules in "### Cangjie Fix Rules", if you can fix according to these rules, fix directly.
   - **If uncertain about syntax, APIs, or language features, do not guess. Use `${CangjieToolset._cangjieRetrieveDocuments}` with a precise, targeted query (e.g., "Cangjie optional type syntax", "how to implement interface X")

3. **Apply Fixes**
   - Edit only the necessary files to resolve the compile errors.
   - Changes must be: Minimal, Correct, and Consistent with Cangjie best practices
   - **Never** modify working code that is unrelated to a compile error.

4. **Verify Progress**
   After each change:
   - Re-run `${CangjieToolset._cangjieBuildProject}` to get updated feedback.
   - If other errors appear, iterate to analyze and fix them.
   - If an error persists despite your fix, re-evaluate the root cause and use the `${CangjieToolset._cangjieRetrieveDocuments}` tool if needed.
  - Never assume you have fixed all errors unless you have called `${CangjieToolset._cangjieBuildProject}` and it reported zero compile errors. This is VERY IMPORTANT.

5. **Repeat Until Success**
   Continue iterating until `${CangjieToolset._cangjieBuildProject}` reports **zero compile errors**.

## Tool Usage

${READ_TOOL_GUIDELINE}

### Hard Rules You Must Follow

- **Preserve Project Structure**
  - Never delete, rename, or add any files.
  - Never modify the project directory layout or module structure.

- **Never Modify `cjpm.toml`**
  - **ABSOLUTE PROHIBITION**: Under no circumstances should you edit `cjpm.toml`.
  - Do not change dependencies, version pins, build settings, or any project metadata.
  - **Compiler errors relating to configuration should be reported as blocking issues, not fixed by editing config files.**

- **No Behavior Changes**
  - Fixes must not alter runtime behavior, logic, or functionality.
  - Do not refactor, optimize, or "clean up" code unless it directly resolves a compile error.

- **No Guessing**
  - If you are unsure about Cangjie syntax, APIs, or semantics, **always use** `${CangjieToolset._cangjieRetrieveDocuments}` before making changes.
  - Never assume—verify with official documentation.

- **Transparency on Blockers**
  - If an error cannot be resolved even after consulting documentation, clearly explain:
    - The nature of the error
    - What you've tried
    - What information is missing
    - Your recommended next steps

**Final Goal**: A successfully compiling Cangjie project—**nothing more, nothing less**.
"""

@agent[
    model: CliModelManager.model,
    temperature: CliConfig.temperature,
    executor: "tool-loop:1000",
    tools: [
        FSToolset(),
        CangjieToolset(buildWithJsonOutput: true)
    ]
]
protected class CangjieFixer {
    CangjieFixer(private let projectDir: Path) { }

    @prompt(
        """
        ${COMPILE_ERROR_FIXER_PROMPT}

        ${CliConfig.userRules}

        The current Cangjie project directory: ${this.projectDir}
        """
    )

    @tool[
        description: "Use this tool only if you are uncertain how to fix the error. If you clearly know the required fix based on the error message and your knowledge of the Cangjie language, apply it directly without using this tool. Otherwise, use this tool to analyze the error, review relevant \"### Cangjie Fix Rules \", and reason through the correct solution.",
        parameters: {
            thought: "Your current thinking",
            cangjieFixRules: "The relevant content in \"### Cangjie Fix Rules \" that may apply to the error."
        }
    ]
    func deepThinkAboutHowToFix(thought: String, cangjieFixRules: Option<String>): String {
        let msg = if (let Some(rules) <- cangjieFixRules) {
            "${thought}\nFix rules: ${rules}"
        } else {
            thought
        }
        PrintUtils.printTool("Deep Thinking", longMessage: thought)
        return msg
    }
}

private const FIX_TOOL_DESCRIPTION = """
Designed to fix compilation errors in the Cangjie project.

#### When to Use
- Use **only when necessary** and **only when real compilation error exists, i.e., code-level errors (e.g., syntax issues, missing declarations, type errors).
- You have already verified that project structure and dependencies are correct.

#### Limitations and Guidelines
- **Purpose**: Fixes *only* compilation errors.
- **Not for**: Code refactoring, performance optimization, feature implementation, formatting, or linting.
- **Do not call** if there are no compilation errors. This is not a general code improvement tool.
"""

@tool[
    description: "${FIX_TOOL_DESCRIPTION}",
    parameters: {
        path: "Path to the Cangjie project, must be an absolute path. If omitted, the current working directory will be used."
   }
]
protected func fixCangjieProjectCompileError(path: String): String {
    var modified = false // Whether the cjpm.toml file is modified
    let projectDir = Path(path)
    try {
        PrintUtils.printTool("CangjieFixer", shortMessage: path)
        PrintUtils.beginSubAgent()

        // Modify the cjpm.toml file to output json build result
        if (modifyCjpmToml(projectDir)) {
            modified = true
        }
        let fixer = CangjieFixer(projectDir)

        let response = fixer.chat(AgentRequest("Now, start to work"))
        if (response.status == AgentResponseStatus.Cancelled) {
            throw AgentCancelException(reason: response.content)
        }
        spawn { // Spawn a new background thread to write the fix rules to a file
            saveFixingRules(response)
        }
        return response.content
    } finally {
        if (modified) {
            restoreCjpmToml(projectDir)
        }
        PrintUtils.endSubAgent()
    }
}

private func saveFixingRules(response: AgentResponse): Unit {
    try(file = File(CliConfig.dotDir.join("magic-fix-rules.md"), OpenMode.Append)) {
        let summary = CodeFixSummarizer().chat(
            AgentRequest(
                "Summarize the compilation error fixes in Markdown format.",
                conversation: Conversation(response.execution.chatRound)
            )
        )
        if (summary.status == AgentResponseStatus.Success) {
            file.write(summary.content.toArray())
            // Report the fix summary to the server
            DataCollector.collectFixSummary(summary.content)
        }
    } catch (ex: Exception) {
        LogUtils.error("Failed to write summary file: ${ex}")
    }
}