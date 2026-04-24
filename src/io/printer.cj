package metis.io

import magic.core.agent.{AsyncAgentResponse, AgentResponse}

import metis.core.plan.{ Plan, Task }
import metis.core.config.CliConfig

import std.fs.OpenMode
import std.collection.{ArrayList, enumerate, map, collectArray}
import std.time.DateTime

/**
 * Abstract printer interface for different output formats
 */
protected interface Printer {
    /**
     * Print a line with optional indentation
     */
    func printLine(line: String, withIndent!: Bool): Unit

    /**
     * Print a string without newline with optional indentation
     */
    func printString(str: String, withIndent!: Bool): Unit

    /**
     * Print a plan
     */
    func printPlan(plan: Plan): Unit

    /**
     * Print tool execution information
     */
    func printTool(name: String, shortMessage: String, longMessage: String, needConfirm!: Bool): Unit

    /**
     * Print tool failure information
     */
    func printToolFailure(toolInfo: String, failure!: String): Unit

    /**
     * Print tool result
     */
    func printToolResult(result: String): Unit

    /**
     * Print agent response
     */
    func printAgentResponse(response: AgentResponse): Unit

    /**
     * Print async agent response
     */
    func printAgentResponse(response: AsyncAgentResponse): Unit

    /**
     * Print shell command result
     */
    func printShellResult(output: String): Unit

    /**
     * Print approval message
     */
    func printApproval(): Unit

    /**
     * Print cancellation message
     */
    func printCancellation(): Unit

    /**
     * Print interrupt message
     */
    func printInterrupt(): Unit

    /**
     * Print user confirmation prompt
     */
    func printUserConfirm(): Unit

    /**
     * Print welcome message
     */
    func printWelcome(): Unit

    /**
     * Print exit message
     */
    func printExitMessage(): Unit

    /**
     * Print logo
     */
    func printLogo(): Unit

    /**
     * For sub-agents
     */
    func beginSubAgent(): Unit
    func endSubAgent(): Unit
    func resetSubAgent(): Unit

    /**
     * Render diff with appropriate formatting
     */
    func renderDiff(content: String): String
}
