package metis.io

import magic.log.LogUtils
import metis.core.config.CliConfig

import std.collection.{ArrayList, LinkedList}
import std.regex.Regex
import std.deriving.*
import std.fs.{File, Path, exists}
import std.time.DateTime

/**
 * Input state management
 */
class InputState {
    public var buffer: LinkedList<Rune>
    public var cursor: Int64
    public var historyIndex: Int64
    public var currentInputCache: Option<String>  // Cache for current input

    public init() {
        this.buffer = LinkedList<Rune>()
        this.cursor = 0
        this.historyIndex = 0
        this.currentInputCache = None
    }

    /**
     * Check if shell mode is active (input starts with !)
     */
    public func isShellMode(): Bool {
        if (this.buffer.size == 0) {
            return false
        }
        return (this.buffer.first ?? r' ') == r'!'
    }

    public func clear() {
        this.buffer.clear()
        this.cursor = 0
    }

    public func getText(): String {
        return String(this.buffer)
    }

    public func insertChar(char: Rune) {
        if (this.cursor == this.buffer.size) {
            this.buffer.addLast(char)
        } else {
            let node = this.buffer.nodeAt(this.cursor).getOrThrow()
            this.buffer.addBefore(node, char)
        }
        this.cursor += 1
    }

    public func deleteChar(): Bool {
        if (this.buffer.size > 0 && this.cursor > 0) {
            if (let Some(node) <- this.buffer.nodeAt(this.cursor - 1)) {
                this.buffer.remove(node)
                this.cursor -= 1
                return true
            }
        }
        return false
    }

    public func deleteCharAt(): Bool {
        if (this.buffer.size > 0 && this.cursor < this.buffer.size) {
            if (let Some(node) <- this.buffer.nodeAt(this.cursor)) {
                this.buffer.remove(node)
                // Cursor stays at same position (character after gets pulled back)
                return true
            }
        }
        return false
    }

    public func moveCursorLeft() {
        this.cursor = max(0, this.cursor - 1)
    }

    public func moveCursorRight() {
        this.cursor = min(this.buffer.size, this.cursor + 1)
    }

    public func setFromHistory(text: String) {
        this.clear()
        for (char in text.toRuneArray()) {
            this.buffer.addLast(char)
        }
        this.cursor = this.buffer.size
    }

    private func isWordChar(r: Rune): Bool {
        return (r >= r'A' && r <= r'Z') || (r >= r'a' && r <= r'z') || (r >= r'0' && r <= r'9')
    }

    private func getCharAt(index: Int64): Option<Rune> {
        if (let Some(node) <- this.buffer.nodeAt(index)) {
            return Some(node.value)
        }
        return None
    }

    public func moveWordLeft() {
        if (this.cursor == 0) { return }

        // Check if current position is on a word char
        if (let Some(ch) <- getCharAt(this.cursor - 1)) {
            if (isWordChar(ch)) {
                // Skip all word chars
                while (this.cursor > 0) {
                    if (let Some(c) <- getCharAt(this.cursor - 1)) {
                        if (!isWordChar(c)) { break }
                    }
                    this.cursor -= 1
                }
            } else {
                // Non-word char (e.g., Chinese): move one char
                this.cursor -= 1
            }
        }
    }

    public func moveWordRight() {
        if (this.cursor >= this.buffer.size) { return }

        // Check if current position is on a word char
        if (let Some(ch) <- getCharAt(this.cursor)) {
            if (isWordChar(ch)) {
                // Skip all word chars
                while (this.cursor < this.buffer.size) {
                    if (let Some(c) <- getCharAt(this.cursor)) {
                        if (!isWordChar(c)) { break }
                    }
                    this.cursor += 1
                }
            } else {
                // Non-word char (e.g., Chinese): move one char
                this.cursor += 1
            }
        }
    }
}

/**
 * Completion state management
 */
private class CompletionState {
    public var completions: Array<String>
    public var selectedIndex: Int64
    public var isActive: Bool

    public init() {
        this.completions = []
        this.selectedIndex = 0
        this.isActive = false
    }

    public func setCompletions(completions: Array<String>) {
        this.completions = completions
        this.selectedIndex = 0
        this.isActive = completions.size > 0
    }

    public func clear() {
        this.completions = []
        this.selectedIndex = 0
        this.isActive = false
    }

    public func moveUp() {
        if (this.isActive && this.completions.size > 0) {
            this.selectedIndex = if (this.selectedIndex > 0) {
                this.selectedIndex - 1
            } else {
                this.completions.size - 1
            }
        }
    }

    public func moveDown() {
        if (this.isActive && this.completions.size > 0) {
            this.selectedIndex = (this.selectedIndex + 1) % this.completions.size
        }
    }

    public func getSelected(): Option<String> {
        if (this.isActive && this.selectedIndex < this.completions.size) {
            return this.completions[this.selectedIndex]
        }
        return None
    }
}

/**
 * Display context for rendering
 */
class DisplayContext {
    public let prompt: String
    public var lastRenderedLines: Int64
    public var totalRenderedLines: Int64
    public var terminalWidth: Int64

    public init(prompt: String) {
        this.prompt = prompt
        this.lastRenderedLines = 0
        this.totalRenderedLines = 0
        this.terminalWidth = 80 // Default width, could be detected from terminal
    }
}

private func styleUserInputText(text: String, isShellMode: Bool): String {
    if (text.isEmpty()) {
        return text
    }
    let foreground = if (isShellMode) {
        AnsiColor.BRIGHT_GREEN
    } else {
        AnsiColor.BRIGHT_WHITE
    }
    return "${Theme.BG_INPUT}${foreground} ${text} ${AnsiColor.RESET}"
}

private func styleUserInputLine(prompt: String, text: String, isShellMode: Bool): String {
    let foreground = if (isShellMode) {
        AnsiColor.BRIGHT_GREEN
    } else {
        AnsiColor.BRIGHT_WHITE
    }
    return "${Theme.BG_INPUT}${foreground}${prompt}${text}${AnsiColor.RESET}"
}

/**
 * Extract @path context based on cursor position
 * Returns (atIndex, pathStart, pathEnd, pathPrefix) or None
 */
func extractPathContext(text: String, cursor: Int64): Option<(Int64, Int64, Int64, String)> {
    let runes = text.toRuneArray()

    // Find the last @ symbol before the current cursor
    var atIndex: Int64 = -1
    let maxIndex = min(cursor, runes.size)
    for (i in 0..maxIndex) {
        let reverseIndex = maxIndex - 1 - i
        if (reverseIndex >= 0 && runes[reverseIndex] == r'@') {
            atIndex = reverseIndex
            break
        }
    }

    if (atIndex == -1) {
        return None
    }

    // Find the first space after the @ symbol
    let pathStart = atIndex + 1
    var pathEnd = runes.size
    for (i in pathStart..runes.size) {
        if (runes[i] == r' ') {
            pathEnd = i
            break
        }
    }

    // Check if the first space is before the current cursor
    // If there's a space before cursor, the path has ended and no completion should show
    if (pathEnd < cursor) {
        return None // Path has ended before cursor
    }

    // Extract path prefix up to cursor position
    let pathPrefix = String(runes[pathStart..cursor])

    return Some((atIndex, pathStart, pathEnd, pathPrefix))
}

/**
 * Render completion list using existing wrapShowList function
 */
private func renderCompletionList(completions: Array<String>, selectedIndex: Int64): String {
    return wrapOptionList(completions, selectedIndex)
}

/**
 * Clear previous render and move cursor to start
 * Uses existing moveCursor and clearScreen functions
 */
private func clearPreviousRender(lines: Int64) {
    if (lines > 0) {
        moveCursor(lines, direction: Direction.Up)
        moveCursor(col: 0)
        clearScreen(mode: ClearMode.AfterCursorScreen)
    }
}

private let READLINE_CANCEL_SENTINEL = "MAGIC_CLI_READLINE_ESC_CANCELLED"

/**
 * Enhanced Readline implementation with improved UI and completion
 */
public class Readline {
    private let history: ArrayList<String>
    private let historyFile: Option<Path>
    private var footnote: Option<String> = None

    public init() {
        this.history = ArrayList<String>()
        this.historyFile = None
    }

    public init(path: Path) {
        this.history = ArrayList<String>()
        this.historyFile = path
        this.loadHistoryFile(path)
    }

    public func setFootnote(footnote: String): Unit {
        this.footnote = Some(footnote)
    }

    private func loadHistoryFile(path: Path): Unit {
        if (!exists(path)) {
            return
        }
        try {
            let content = String.fromUtf8(File.readFrom(path))
            for (line in content.split("\n")) {
                if (!line.isEmpty()) {
                    this.history.add(line)
                }
            }
        } catch (e: Exception) {
            LogUtils.error("Failed to read readline history file")
        }
    }

    private func appendHistoryFile(line: String): Unit {
        if (line.isEmpty()) {
            return
        }
        if (let Some(path) <- this.historyFile) {
            File.appendTo(path, "${line}\n".toArray())
        }
    }

    /**
     * Apply selected completion to input state
     */
    private func applyCompletion(
        inputState: InputState,
        completionState: CompletionState,
        selected: String
    ) {
        let currentText = inputState.getText()
        var newText = ""
        var newCursor: Int64 = inputState.cursor

        // Handle @path completion
        if (let Some((atIndex, pathStart, pathEnd, pathPrefix)) <- extractPathContext(currentText, inputState.cursor)) {
            // Replace the path part with selected path
            // Use rune-based operations to handle multi-byte characters correctly
            let runes = currentText.toRuneArray()
            let beforePathRunes = runes[0..pathStart]
            let afterPathRunes = runes[pathEnd..]
            let selectedRunes = selected.toRuneArray()

            // Reconstruct text using rune arrays
            newText = String(beforePathRunes) + selected + String(afterPathRunes)
            // Set cursor to end of inserted path (in rune/character count)
            newCursor = beforePathRunes.size + selectedRunes.size
        }
        // Handle /command completion
        else if (currentText.startsWith("/")) {
            newText = selected
            newCursor = selected.toRuneArray().size
        }
        else {
            newText = selected
            newCursor = selected.toRuneArray().size
        }

        // Replace buffer with new text
        inputState.clear()
        for (char in newText.toRuneArray()) {
            inputState.buffer.addLast(char)
        }
        inputState.cursor = newCursor
        completionState.clear()

        // Update completion list for further completions
        if (let Some(newCompletions) <- buildCompletionList(newText, inputState.cursor, isShellMode: inputState.isShellMode())) {
            completionState.setCompletions(newCompletions)
        }
    }

    /**
     * Handle key input and return result
     */
    private func handleInput(
        rune: Rune,
        inputState: InputState,
        completionState: CompletionState,
        displayContext: DisplayContext,
        cancelOnEsc!: Bool = false
    ): Option<String> {
        match (rune) {
            case r'\r' | r'\n' => // Enter
                // If completion is active, accept it first
                if (completionState.isActive) {
                    if (let Some(selected) <- completionState.getSelected()) {
                        this.applyCompletion(inputState, completionState, selected)
                        return None
                    }
                }
                // If \n is not the last character, handle it as a regular character
                if (RawInputUtils.hasInput()) {
                    handleRune(rune, inputState, completionState)
                    return None
                }

                // Otherwise, finalize input
                let text = inputState.getText()

                // Clear the current input cache when submitting
                inputState.currentInputCache = None

                if (text.size > 0) {
                    this.history.add(text)
                    this.appendHistoryFile(text)
                }
                return text

            case r'\u{7F}' | r'\b' => // Backspace - delete character before cursor
                if (inputState.deleteChar()) {
                    // Always clear completions when deleting characters
                    completionState.clear()

                    // Update completion list based on new text
                    let newText = inputState.getText()
                    if (!newText.isEmpty()) {
                        if (let Some(completions) <- buildCompletionList(newText, inputState.cursor, isShellMode: inputState.isShellMode())) {
                            completionState.setCompletions(completions)
                        }
                    }
                }
                return None

            case r'\u{4}' => // Ctrl+D
                // Check if buffer is empty - Ctrl+D on empty line should exit
                if (inputState.buffer.size == 0) {
                    // Empty line - Ctrl+D sends EOF and exits the program
                    return Some("/exit")
                }

                // Non-empty line - Ctrl+D acts as delete-char
                if (inputState.deleteCharAt()) {
                    // Always clear completions when deleting characters
                    completionState.clear()

                    // Update completion list based on new text
                    let newText = inputState.getText()
                    if (!newText.isEmpty()) {
                        if (let Some(completions) <- buildCompletionList(newText, inputState.cursor, isShellMode: inputState.isShellMode())) {
                            completionState.setCompletions(completions)
                        }
                    }
                }
                return None

            case r'\u{2326}' => // Delete key (⌦) - mapped from ESC[3~ in FFI
                if (inputState.deleteCharAt()) {
                    // Always clear completions when deleting characters
                    completionState.clear()

                    // Update completion list based on new text
                    let newText = inputState.getText()
                    if (!newText.isEmpty()) {
                        if (let Some(completions) <- buildCompletionList(newText, inputState.cursor, isShellMode: inputState.isShellMode())) {
                            completionState.setCompletions(completions)
                        }
                    }
                }
                return None

            case r'\t' => // Tab
                if (completionState.isActive) {
                    if (let Some(selected) <- completionState.getSelected()) {
                        this.applyCompletion(inputState, completionState, selected)
                    }
                }
                return None

            case r'\u{2191}' => // Up ↑
                if (completionState.isActive) {
                    completionState.moveUp()
                } else {
                    // Navigate history
                    if (inputState.historyIndex > 0) {
                        // Save current input to cache when first navigating away from new input
                        if (inputState.historyIndex == this.history.size) {
                            inputState.currentInputCache = Some(inputState.getText())
                        }
                        inputState.historyIndex -= 1
                        inputState.setFromHistory(this.history[inputState.historyIndex])
                    }
                }
                return None

            case r'\u{2193}' => // Down ↓
                if (completionState.isActive) {
                    completionState.moveDown()
                } else {
                    // Navigate history
                    if (inputState.historyIndex + 1 < this.history.size) {
                        inputState.historyIndex += 1
                        inputState.setFromHistory(this.history[inputState.historyIndex])
                    } else if (inputState.historyIndex + 1 == this.history.size) {
                        inputState.historyIndex = this.history.size
                        // Restore cached current input when navigating back to bottom
                        if (let Some(cached) <- inputState.currentInputCache) {
                            inputState.setFromHistory(cached)
                        } else {
                            inputState.clear()
                        }
                        // Clear the cache after restoring
                        inputState.currentInputCache = None
                    }
                }
                return None

            case r'\u{2190}' => // Left ←
                inputState.moveCursorLeft()
                // Update completion list after cursor movement
                let newText = inputState.getText()
                if (let Some(completions) <- buildCompletionList(newText, inputState.cursor, isShellMode: inputState.isShellMode())) {
                    completionState.setCompletions(completions)
                } else {
                    completionState.clear()
                }
                return None

            case r'\u{2192}' => // Right →
                inputState.moveCursorRight()
                // Update completion list after cursor movement
                let newText = inputState.getText()
                if (let Some(completions) <- buildCompletionList(newText, inputState.cursor, isShellMode: inputState.isShellMode())) {
                    completionState.setCompletions(completions)
                } else {
                    completionState.clear()
                }
                return None

            case r'\u{2B05}' => // Ctrl+Left
                inputState.moveWordLeft()
                completionState.clear()
                return None

            case r'\u{27A1}' => // Ctrl+Right
                inputState.moveWordRight()
                completionState.clear()
                return None

            case r'\u{1}' => // Home (Ctrl+A) / Home key
                // Move cursor to beginning of line
                inputState.cursor = 0
                // Update completion list after cursor movement
                let newText = inputState.getText()
                if (let Some(completions) <- buildCompletionList(newText, inputState.cursor, isShellMode: inputState.isShellMode())) {
                    completionState.setCompletions(completions)
                } else {
                    completionState.clear()
                }
                return None

            case r'\u{5}' => // End (Ctrl+E) / End key
                // Move cursor to end of line
                inputState.cursor = inputState.buffer.size
                // Update completion list after cursor movement
                let newText = inputState.getText()
                if (let Some(completions) <- buildCompletionList(newText, inputState.cursor, isShellMode: inputState.isShellMode())) {
                    completionState.setCompletions(completions)
                } else {
                    completionState.clear()
                }
                return None

            case r'\u{1B}' => // ESC
                if (cancelOnEsc) {
                    return READLINE_CANCEL_SENTINEL
                }
                return None // Could be used to cancel completion or exit

            case _ => // Regular character
                handleRune(rune, inputState, completionState)
                return None
        }
    }

    private func handleRune(rune: Rune,
                            inputState: InputState,
                            completionState: CompletionState): Unit {
        inputState.insertChar(rune)

        // Update completion list
        let newText = inputState.getText()
        if (let Some(completions) <- buildCompletionList(newText, inputState.cursor, isShellMode: inputState.isShellMode())) {
            completionState.setCompletions(completions)
        } else {
            completionState.clear()
        }
    }

    /**
     * Render the current state following the original redraw pattern
     * Uses borderless wrapped input with proper positioning
     * Different colors are used in shell mode
     */
    private func render(
        inputState: InputState,
        completionState: CompletionState,
        displayContext: DisplayContext,
        isFirst!: Bool = false
    ) {
        // Create current and previous drawing state
        let currentText = inputState.getText()
        let isShellMode = inputState.isShellMode()

        let useInputBoxBorder = false
        let textColor = if (isShellMode) { AnsiColor.BRIGHT_GREEN } else { "" }

        // Apply colors to both prompt and text in shell mode
        let displayPrompt = if (isShellMode) {
            "${textColor}${displayContext.prompt}${AnsiColor.RESET}"
        } else {
            displayContext.prompt
        }

        let displayText = currentText

        var wrappedContent = if (useInputBoxBorder) {
            wrapBox(styleUserInputLine(displayPrompt, displayText, isShellMode))
        } else {
            wrapInput(styleUserInputLine(displayPrompt, displayText, isShellMode))
        }

        // Append footnote if set
        if (let Some(footnote) <- this.footnote) {
            if (!footnote.trimAscii().isEmpty()) {
                wrappedContent = wrappedContent + "\n" + footnote
            }
        }

        // Calculate cursor position for current state
        let (cursorRow, cursorCol) = calculateCursorPos(
            inputState,
            displayContext
        )

        // Clear previous render (similar to original redraw logic)
        if (!isFirst) {
            if (displayContext.lastRenderedLines > 0) {
                // Move up based on previous cursor position
                moveCursor(displayContext.lastRenderedLines, direction: Direction.Up)
            }
            moveCursor(col: 0)
            clearScreen(mode: ClearMode.AfterCursorScreen)
        }

        // Print the wrapped content
        PrintUtils.printString(wrappedContent)

        // Handle completion list (similar to extendLine in original)
        if (completionState.isActive) {
            let completionText = renderCompletionList(
                completionState.completions,
                completionState.selectedIndex
            )
            if (!completionText.isEmpty()) {
                let completionLines = completionText.lines().count() - 1
                PrintUtils.printString(completionText)
                // Move cursor up by completion lines
                if (completionLines > 0) {
                    moveCursor(completionLines, direction: Direction.Up)
                }
            }
        }

        // Move cursor to correct position (following original pattern)
        let totalLines = wrappedContent.lines().count()
        let borderOffset = if (useInputBoxBorder) { 2 } else { 1 }
        let linesToMoveUp = totalLines - cursorRow - borderOffset
        if (linesToMoveUp > 0) {
            moveCursor(linesToMoveUp, direction: Direction.Up)
        }
        moveCursor(col: cursorCol)

        // Store cursor row for next cycle (not total lines)
        let topOffset = if (useInputBoxBorder) { 1 } else { 0 }
        displayContext.lastRenderedLines = cursorRow + topOffset
        displayContext.totalRenderedLines = totalLines
    }

    /**
     * Final render when input is complete (similar to DrawPhase.Last)
     * Positions cursor at the bottom of the input area
     * Uses shell mode colors if active
     */
    private func renderFinal(inputState: InputState, displayContext: DisplayContext) {
        let currentText = inputState.getText()
        let isShellMode = inputState.isShellMode()

        let useInputBoxBorder = false
        let textColor = if (isShellMode) { AnsiColor.BRIGHT_GREEN } else { "" }

        let displayPrompt = if (isShellMode) {
            "${textColor}${displayContext.prompt}${AnsiColor.RESET}"
        } else {
            displayContext.prompt
        }

        let displayText = currentText

        let wrappedContent = if (useInputBoxBorder) {
            wrapBox(styleUserInputLine(displayPrompt, displayText, isShellMode))
        } else {
            wrapInput(styleUserInputLine(displayPrompt, displayText, isShellMode))
        }

        if (displayContext.lastRenderedLines > 0) {
            moveCursor(displayContext.lastRenderedLines, direction: Direction.Up)
        }
        moveCursor(col: 0)
        clearScreen(mode: ClearMode.AfterCursorScreen)
        PrintUtils.printString(wrappedContent)
        PrintUtils.printLine("")
        displayContext.lastRenderedLines = 0
        displayContext.totalRenderedLines = 0
    }

    /**
     * Main readline function
     */
    private func readlineInternal(prompt: String, cancelOnEsc!: Bool = false): Option<String> {
        try {
            // RawInputUtils.rawEnter()

            let inputState = InputState()
            let completionState = CompletionState()
            let displayContext = DisplayContext(prompt)
            inputState.historyIndex = this.history.size

            // Initial render (first time)
            this.render(inputState, completionState, displayContext, isFirst: true)

            while (true) {
                let rune = if (let Some(r) <- RawInputUtils.getRune()) {
                    r
                } else {
                    return None // EOF
                }

                let result = this.handleInput(
                    rune,
                    inputState,
                    completionState,
                    displayContext,
                    cancelOnEsc: cancelOnEsc
                )

                if (let Some(line) <- result) {
                    if (cancelOnEsc && line == READLINE_CANCEL_SENTINEL) {
                        inputState.clear()
                        this.renderFinal(inputState, displayContext)
                        return None
                    }
                    // Final render to position cursor at bottom of input box (like DrawPhase.Last)
                    this.renderFinal(inputState, displayContext)
                    return line
                } else {
                    // Re-render after handling input (not first time)
                    this.render(inputState, completionState, displayContext, isFirst: false)
                }
            }

            return None
        } finally {
            // RawInputUtils.rawExit()
        }
    }

    public func readline(prompt: String): Option<String> {
        return this.readlineInternal(prompt)
    }

    public func readlineWithCancel(prompt: String): Option<String> {
        return this.readlineInternal(prompt, cancelOnEsc: true)
    }

    /**
     * Simple blocking readline without fancy UI
     */
    public func simpleReadLine(prompt: String): Option<String> {
        PrintUtils.printString(prompt)
        return readln()
    }

    /**
     * Conditional readline based on withBox parameter
     */
    public func readline(prompt: String, withBox!: Bool): Option<String> {
        if (withBox) {
            return this.readline(prompt)
        } else {
            return this.simpleReadLine(prompt)
        }
    }

    public func readlineWithCancel(prompt: String, withBox!: Bool): Option<String> {
        if (withBox) {
            return this.readlineWithCancel(prompt)
        } else {
            return this.simpleReadLine(prompt)
        }
    }
}
