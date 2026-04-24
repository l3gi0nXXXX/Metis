package metis.io

import magic.log.LogUtils
import magic.core.tool.ToolException

import metis.core.config.CliConfig
import metis.core.plan.{ Plan, Task }
import metis.utils.InfoUtils
import std.collection.{map, enumerate, collectArray}
import std.time.DateTime
import std.sync.AtomicBool
import std.deriving.Derive
import std.collection.ArrayList

@Derive[ToString, Equatable]
protected enum Confirmation {
    | Approve
    | Deny
}

protected class InputUtils {
    // Global flag to coordinate between ESC checker and user input
    private static var isRequestingUserInput: AtomicBool = AtomicBool(false)
    // Prevent background reads from stealing terminal input.
    private static var terminalInputLocked: AtomicBool = AtomicBool(false)
    // Track whether raw mode is enabled in this process.
    private static var rawModeEnabled: AtomicBool = AtomicBool(false)

    protected static let readline = Readline(CliConfig.readlineFile)

    public static func enterRawMode(): Unit {
        if (rawModeEnabled.load()) {
            return
        }
        RawInputUtils.rawEnter()
        rawModeEnabled.store(true)
    }

    public static func exitRawMode(): Unit {
        if (!rawModeEnabled.load()) {
            return
        }
        RawInputUtils.rawExit()
        rawModeEnabled.store(false)
    }

    private static func shouldUseCookedPrompt(): Bool {
        return InfoUtils.os == "macos"
    }

    public static func buildPrompt(prompt: String): String {
        return " ${prompt} > ".withColor(Theme.MUTED)
    }

    /**
     * macOS cooked input uses terminal-native line editing.
     * A colored / wide-character prompt (for example ANSI-colored "🔮 > ")
     * can leave a stray cell behind when deleting CJK runes with backspace.
     * Use a plain ASCII prompt for the actual cooked read, then keep the
     * styled replay after submission.
     */
    private static func buildCookedReadPrompt(prompt: String): String {
        let plainPrompt = removeAnsiEscape(prompt)
        let normalized = if (plainPrompt.contains("🔮")) {
            " > "
        } else if (plainPrompt.trimAscii().isEmpty()) {
            " > "
        } else {
            plainPrompt
        }
        normalized
    }

    private static func renderCookedSubmittedInput(prompt: String, input: String): Unit {
        let styledLine = "${Theme.BG_INPUT}${AnsiColor.BRIGHT_WHITE}${prompt}${input}${AnsiColor.RESET}"
        moveCursor(1, direction: Direction.Up)
        moveCursor(col: 0)
        clearScreen(mode: ClearMode.EntireLine)
        PrintUtils.printLine(wrapInput(styledLine))
        PrintUtils.printLine("")
    }

    public static func getUserInput(prompt!: Option<String> = None, withBox!: Bool = true): String {
        // Signal that we're requesting user input
        isRequestingUserInput.store(true)
        try {
            if (shouldUseCookedPrompt() && prompt.isSome()) {
                let targetPrompt = prompt ?? buildPrompt("🔮")
                let cookedPrompt = buildCookedReadPrompt(targetPrompt)
                let restoreRaw = rawModeEnabled.load()
                if (restoreRaw) {
                    exitRawMode()
                }
                try {
                    let input = readline.simpleReadLine(cookedPrompt) ?? "exit"
                    renderCookedSubmittedInput(targetPrompt, input)
                    return input
                } finally {
                    if (restoreRaw) {
                        enterRawMode()
                    }
                }
            }
            return readline.readline(prompt ?? buildPrompt("🔮"), withBox: withBox) ?? "exit"
        } finally {
            // Clear the flag when done
            isRequestingUserInput.store(false)
        }
    }

    public static func getUserInputOrCancel(prompt!: Option<String> = None, withBox!: Bool = true): Option<String> {
        isRequestingUserInput.store(true)
        try {
            return readline.readlineWithCancel(prompt ?? buildPrompt("🔮"), withBox: withBox)
        } finally {
            isRequestingUserInput.store(false)
        }
    }

    public static func isRequestingInput(): Bool {
        return isRequestingUserInput.load()
    }

    public static func lockTerminalInput(): Unit {
        terminalInputLocked.store(true)
    }

    public static func unlockTerminalInput(): Unit {
        terminalInputLocked.store(false)
    }

    public static func isTerminalInputLocked(): Bool {
        return terminalInputLocked.load()
    }

    /**
     * Check if user pressed ESC key
     */
    public static func checkEsc(): Bool {
        let VK_ESCAPE: Byte = 0x1B
        if (RawInputUtils.checkReadByte([VK_ESCAPE], infinite: false)) {
            return true
        } else {
            return false
        }
    }

    private static func showTaskTree(task: Task, indentLevel: Int64, outputTaskStringList: ArrayList<String>, indent!: Int64 = 2): Unit {
        let descriptionCombo = task.description
        outputTaskStringList.add(" " * indentLevel * indent + "${'╰─'.withColor(AnsiColor.BRIGHT_BLACK)} ${descriptionCombo.withColor(AnsiColor.BOLD)}")

        for (subtask in task.subtasks) {
            showTaskTree(subtask, indentLevel + 1, outputTaskStringList, indent: indent)
        }
    }

    public static func confirm(task: Task) {
        let tasks = ArrayList<String>()
        showTaskTree(task, 0, tasks)
        let footer = "💡 Subtasks have been created. Please confirm if you need to modify the subtasks. ʘ‿ʘ".withColor(Theme.HIGHLIGHT)

        return confirm("Subtasks", "", String.join(tasks.toArray(), delimiter: "\n"), footer: footer)
    }

    public static func confirm(plan: Plan): Confirmation {
        let tasks = ArrayList<String>()
        for (task in plan.topLevelTasks) {
            showTaskTree(task, 0, tasks)
        }
        let footer = "💡 Plan has been created. Please confirm if you need to modify the plan. ʘ‿ʘ".withColor(Theme.HIGHLIGHT)
        return confirm("Plan", "", String.join(tasks.toArray(), delimiter: "\n"), footer: footer)
    }

    public static func confirm(title: String, shortMessage: String, longMessage: String, footer!: Option<String> = None): Confirmation {
        PrintUtils.printTool(title, shortMessage: shortMessage, longMessage: longMessage, needConfirm: !CliConfig.auto)
        if (let Some(footer) <- footer) {
            PrintUtils.printLine(footer)
            PrintUtils.printLine("")
        }
        if (CliConfig.auto) {
            return Confirmation.Approve
        }
        // Signal that we're requesting user input
        isRequestingUserInput.store(true)
        try {
            let options = [
                "Yes, proceed",
                "Yes, allow all edits during this session",
                "No, and tell Metis what to do differently"
            ]
            match (getOptions(options)) {
                case Some(index) =>
                    if (index == 0) {
                        PrintUtils.printApproval()
                        return Confirmation.Approve
                    } else if (index == 1) {
                        PrintUtils.printApproval()
                        CliConfig.auto = true
                        return Confirmation.Approve
                    } else {
                        let input = getUserInput(prompt: "> ")
                        throw ToolException("User denied the tool to run with guidelines: \"${input}\".\nNOTE You must follow her/his guidelines to execute. Remember that obeying user guidelines is the most important.")
                    }
                case None => // User pressed ESC to cancel
                    PrintUtils.printCancellation()
                    return Confirmation.Deny
            }
        } finally {
            // Clear the flag when done
            isRequestingUserInput.store(false)
        }
    }

    /**
     * Allow user to select an option from a list using arrow keys
     * @param options Array of options to display
     * @param prompt Optional prompt message
     * @return Index of the selected option (0-based)
     */
    public static func getOptions(options: Array<String>, prompt!: Option<String> = None): Option<Int64> {
        if (options.isEmpty()) {
            return None
        }
        var selectedIndex = 0
        var isFirstRender = true
        // The clean auxiliary function
        let clearOptionsFn = { =>
            // prompt + #options
            let linesToClear = if (prompt.isSome()) { 1 + options.size } else { options.size }
            // Move cursor up to clear previous display
            moveCursor(linesToClear, direction: Direction.Up)
            clearScreen(mode: ClearMode.AfterCursorScreen)
        }
        while (true) {
            // Clear previous render
            if (!isFirstRender) {
                clearOptionsFn()
            }
            // Construct the options to display
            let select = selectedIndex // var variables cannot be captured by lambda
            let optionsToDisplay = options |> enumerate |> map { tuple =>
                let itemIndex = tuple[0]
                let item = tuple[1]
                if (itemIndex == select) {
                    // Highlight the selected item
                    return "◉ ${AnsiColor.BRIGHT_BLUE}${AnsiColor.BOLD}${item}${AnsiColor.RESET}"
                } else {
                    // Normal display for unselected items
                    return "○ ${AnsiColor.BRIGHT_BLACK}${item}${AnsiColor.RESET}"
                }
            } |> collectArray
            // Display prompt and options
            if (let Some(line) <- prompt) {
                PrintUtils.printLine(line.withColor(Theme.MUTED))
            }
            PrintUtils.printLine(String.join(optionsToDisplay, delimiter: "\n"))

            // Read keyboard input
            let rune = RawInputUtils.getRune()
            if (rune.isNone()) {
                return None // EOF or error
            }
            match (rune.getOrThrow()) {
                case r'\r' | r'\n' => // Enter key
                    break
                case r'\u{2191}' | r'k' => // Up ↑
                    if (selectedIndex > 0) {
                        selectedIndex -= 1
                    } else {
                        selectedIndex = options.size - 1 // Wrap to last
                    }
                case r'\u{2193}' | r'j' => // Down ↓
                    if (selectedIndex < options.size - 1) {
                        selectedIndex += 1
                    } else {
                        selectedIndex = 0 // Wrap to first
                    }
                case r'\u{1B}' => // ESC
                    selectedIndex = -1
                    break
                case _ => () // Ignore other keys
            }

            isFirstRender = false
        }
        // Clear the display before returning
        clearOptionsFn()
        if (selectedIndex == -1) {
            return None
        }
        return selectedIndex
    }
}
