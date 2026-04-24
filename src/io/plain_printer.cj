package metis.io

import magic.core.agent.{AsyncAgentResponse, AgentResponse}
import metis.core.config.CliConfig
import metis.core.plan.{ Plan, Task }
import std.fs.OpenMode
import std.collection.{ArrayList, enumerate, map, collectArray}
import std.time.DateTime

/**
 * PlainPrinter - Generates plain text format for file output
 * Removes ANSI colors and converts box decorations to plain text formatting
 * This printer is enabled when non-interactive mode is enabled
 */
protected class PlainPrinter <: Printer {
    /**
     * Non-interactive mode does not support sub-agent indentation
     */
    public func resetSubAgent(): Unit { }
    public func beginSubAgent(): Unit { }
    public func endSubAgent(): Unit { }

    public func printLine(line: String, withIndent!: Bool = false): Unit {
        let cleanLine = removeAnsiEscape(line)
        println(cleanLine)
    }

    public func printString(str: String, withIndent!: Bool = false): Unit {
        let cleanStr = removeAnsiEscape(str)
        print(cleanStr, flush: true)
    }

    private func printTask(task: Task, indentLevel!: Int64 = 0, indent!: Int64 = 2): Unit {
        let descriptionCombo = task.description
        var line: String = ""
        if (task.completed) {
            line = " " * indentLevel * indent + "╰─ ✓ ${descriptionCombo}"
        } else {
            line = " " * indentLevel * indent + "╰─ □ ${descriptionCombo}"
        }
        printLine(line)
        for (subtask in task.subtasks) {
            printTask(subtask, indentLevel: indentLevel + 1, indent: indent)
        }
    }

    public func printPlan(plan: Plan): Unit {
        PrintUtils.printLine("✨ Plan")
        for (task in plan.topLevelTasks) {
            printTask(task)
        }
    }

    public func printTool(name: String, shortMessage: String, longMessage: String, needConfirm!: Bool = false): Unit {
        let cleanName = removeAnsiEscape(name)
        let cleanShortMessage = removeAnsiEscape(shortMessage)
        let cleanLongMessage = removeAnsiEscape(longMessage)
        let strBuilder = StringBuilder("## Tool: ${cleanName}")
        if (!cleanShortMessage.isEmpty()) {
            strBuilder.append(" (${cleanShortMessage})")
        }
        if (!cleanLongMessage.isEmpty()) {
            strBuilder.append("\n\n${cleanLongMessage}")
        }
        let markdownContent = strBuilder.toString()
        printLine(markdownContent)
        printLine("")
    }

    public func printToolFailure(toolInfo: String, failure!: String = "Failed ..."): Unit {
        let cleanToolInfo = removeAnsiEscape(toolInfo)
        let cleanFailure = removeAnsiEscape(failure)

        printLine(cleanToolInfo)
        printLine("- ${cleanFailure}")
    }

    public func printToolResult(result: String): Unit {
        let cleanResult = removeAnsiEscape(result)
        printLine("### Tool Result\n")
        printLine(cleanResult)
        printLine("")
    }

    public func printAgentResponse(response: AgentResponse): Unit {
        printLine("---\n")
        printLine("## Agent Response\n")
        printLine(response.content)
        printLine("")
    }

    public func printAgentResponse(response: AsyncAgentResponse): Unit {
        printLine("---\n")
        printLine("## Agent Response\n")
        printLine(response.content)
        printLine("")
    }

    public func printShellResult(output: String): Unit {
        printLine("```bash")
        printLine(output)
        printLine("```")
    }

    public func printApproval(): Unit {
        throw UnsupportedException("Approval is not supported in markdown printer")
    }

    public func printCancellation(): Unit {
        throw UnsupportedException("Cancellation is not supported in markdown printer")
    }

    public func printInterrupt(): Unit {
        throw UnsupportedException("Interrupt is not supported in markdown printer")
    }

    public func printUserConfirm(): Unit {
        throw UnsupportedException("User confirm is not supported in markdown printer")
    }

    public func printWelcome(): Unit {
        throw UnsupportedException("Welcome is not supported in markdown printer")
    }

    public func printLogo(): Unit {
        throw UnsupportedException("Logo is not supported in markdown printer")
    }

    public func printExitMessage(): Unit {
        throw UnsupportedException("Exit message is not supported in markdown printer")
    }

    public func renderDiff(content: String): String {
        let lines = content.split("\n")
        let result = ArrayList<String>()

        for (line in lines) {
            if (line.startsWith("+")) {
                result.add("+${removeAnsiEscape(line[1..])}")  // Keep + prefix for markdown diff
            } else if (line.startsWith("-")) {
                result.add("-${removeAnsiEscape(line[1..])}")  // Keep - prefix for markdown diff
            } else if (line.startsWith("@@")) {
                result.add(removeAnsiEscape(line))  // Remove colors but keep format
            } else {
                result.add(" ${removeAnsiEscape(line)}")  // Add space for context lines
            }
        }

        return String.join(result.toArray(), delimiter: "\n")
    }
}