package metis.io

import magic.core.agent.{AsyncAgentResponse, AgentResponse}
import magic.log.LogUtils

import metis.core.plan.Plan

import metis.core.config.CliConfig

protected class PrintUtils {
    // Printer instances - lazy initialization
    private static var _printer: Option<Printer> = None

    // Get the appropriate printer based on the current mode
    private static func getPrinter(): Printer {
        if (let Some(printer) <- _printer) {
            return printer
        }
        _printer = if (CliConfig.nonInteractive) {
            // Use MarkdownPrinter for non-interactive mode (--prompt option)
            match (CliConfig.nonInteractiveOutputFormat) {
                case "plain" => PlainPrinter()
                case "markdown" => MarkdownPrinter()
                case _ =>
                    LogUtils.error("Invalid non-interactive output format: ${CliConfig.nonInteractiveOutputFormat}")
                    MarkdownPrinter()
            }
        } else {
            // Use ColorfulPrinter for interactive mode
            ColorfulPrinter()
        }
        return _printer.getOrThrow()
    }

    //--------------------------------------------------------
    // Sub-agent indentation management
    static public func resetSubAgent(): Unit {
        getPrinter().resetSubAgent()
    }

    static public func beginSubAgent(): Unit {
        getPrinter().beginSubAgent()
    }

    static public func endSubAgent(): Unit {
        getPrinter().endSubAgent()
    }

    //---------------------------------------------------
    // Two fundamental print methods
    static public func printLine(line: String, withIndent!: Bool = false): Unit {
        getPrinter().printLine(line, withIndent: withIndent)
    }

    static public func printString(str: String, withIndent!: Bool = false): Unit {
        getPrinter().printString(str, withIndent: withIndent)
    }
    //---------------------------------------------------

    static public func clearScreen(): Unit {
        // Only clear screen in interactive mode
        if (!CliConfig.nonInteractive) {
            moveCursor(row: 0, col: 0)
            clearScreen(mode: AfterCursorScreen)
        }
    }

    static public func printWelcome() {
        getPrinter().printWelcome()
    }

    static public func printLogo() {
        getPrinter().printLogo()
    }

    static public func printExitMessage() {
        getPrinter().printExitMessage()
    }

    static public func printNoteBox(title: String, content: String): Unit {
        printLine(wrapBox(title, content: content))
    }

    static public func renderAssistantResponseBox(content: String): String {
        wrapBox(
            "Metis",
            content: renderMarkdown(removeAnsiEscape(content)),
            withBorder: true
        )
    }

    static public func printPlan(plan: Plan): Unit {
        getPrinter().printPlan(plan)
    }

    //----------------------------------------------------------------------------------
    // The following print methods are called by different components
    //----------------------------------------------------------------------------------
    static public func printProcedure(procedure: String, message: String): Unit {
        // Internally, we use printTool to print the action and result
        printTool(procedure, shortMessage: message)
    }

    static public func printProcedureFailure(procedure: String, failure!: String): Unit {
        // Internally, we use printTool to print the action and result
        printToolFailure(procedure, failure: failure)
    }

    //----------------------------------------------------------------------------------
    // The following print methods are called by tools
    //----------------------------------------------------------------------------------

    static public func printInterrupt() {
        getPrinter().printInterrupt()
    }

    static public func printUserConfirm() {
        getPrinter().printUserConfirm()
    }

    static public func printApproval(): Unit {
        getPrinter().printApproval()
    }

    static public func printCancellation(): Unit {
        getPrinter().printCancellation()
    }

    static public func printTool(name: String, shortMessage!: String, longMessage!: String = "", needConfirm!: Bool = false) {
        getPrinter().printTool(name, shortMessage, longMessage, needConfirm: needConfirm)
    }

    static public func printTool(name: String, longMessage!: String, needConfirm!: Bool = false) {
        printTool(name, shortMessage: "", longMessage: longMessage, needConfirm: needConfirm)
    }


    static public func printToolFailure(toolInfo: String, failure!: String = "Failed ...") {
        getPrinter().printToolFailure(toolInfo, failure: failure)
    }

    static public func printToolResult(result: String, maxLength!: Int64 = 200): Unit {
        let runes = result.toRuneArray()
        let truncated = if (runes.size > maxLength) {
            let truncatedRunes = runes[0..maxLength]
            "${String(truncatedRunes)}\n... [truncated ${runes.size - maxLength} chars]"
        } else {
            result
        }
        getPrinter().printToolResult(truncated)
    }

    //----------------------------------------------------------------------------------

    static public func printAgentResponse(response: AgentResponse) {
        getPrinter().printAgentResponse(response)
    }

    static public func printAgentResponse(response: AsyncAgentResponse) {
        getPrinter().printAgentResponse(response)
    }

    static public func printShellResult(output: String) {
        getPrinter().printShellResult(output)
    }

    static public func printStatusIndicator(message!: String = "Working"): StatusIndicator {
        // Status indicator only makes sense in interactive mode
        if (!CliConfig.nonInteractive) {
            let indicator = StatusIndicator(message)
            indicator.start()
            return indicator
        } else {
            // Return a dummy indicator for non-interactive mode
            return StatusIndicator(message)
        }
    }

    static public func renderDiff(content: String): String {
        return getPrinter().renderDiff(content)
    }
}
