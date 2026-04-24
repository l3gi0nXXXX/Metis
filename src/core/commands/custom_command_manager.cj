package metis.core.commands

import magic.dsl.*
import magic.prelude.*
import magic.jsonable.*
import magic.agent.ConversationAgent
import magic.log.LogUtils
import magic.utils.readFile

import metis.core.config.CliConfig
import metis.io.{PrintUtils, CompletionListUtils, wrapBox, WithColor, Theme, AnsiColor, Align}
import metis.utils.loadMarkdown

import std.fs.{exists, Directory, Path, File}
import std.collection.{HashMap, ArrayList, enumerate, filter, map, collectArray}
import std.regex.{Regex, RegexFlag}
import stdx.encoding.json.*

private struct ParseResult {
    public let options: HashMap<String, String>
    public let remaining: String

    public init(options: HashMap<String, String>, remaining: String) {
        this.options = options
        this.remaining = remaining
    }
}

/**
 * Parses command-line arguments into options and remaining text.
 * Options are expected to be in the form "--key value" or "--key" for flags.
 * Non-option arguments are collected after the first non-option token.
 *
 * @param input Command-line input string
 * @return ParseResult containing parsed options and remaining text
 */
private func parseArgs(input: String): ParseResult {
    let options = HashMap<String, String>()
    var remaining = ""

    // Split by spaces to process tokens
    let tokens = input.split(" ")
    var i = 0
    var foundNonOption = false

    while (i < tokens.size) {
        let token = tokens[i]

        // If we encounter a non-option token, collect remaining text
        if (!token.startsWith("--")) {
            foundNonOption = true
            remaining = String.join(tokens[i..], delimiter: " ")
            break
        }

        // Parse option
        let optionName = token.removePrefix("--")

        // Check if there's a value for this option
        if (i + 1 < tokens.size && !tokens[i + 1].startsWith("--")) {
            let optionValue = tokens[i + 1]
            options[optionName] = optionValue
            i += 2 // Skip both option and value
        } else {
            // Option without value, treat as flag with "true"
            options[optionName] = "true"
            i += 1
        }
    }

    return ParseResult(options, remaining)
}

//-----------------------------------------------------------------------

@jsonable
protected class CustomCommand {
    let description: String
    let arguments: Array<String>
    let content: String
}

protected class CustomCommandManager {
    private var commands = HashMap<String, CustomCommand>()

    public init() {
        registerBuiltinCommands()
        this.loadCommands()
    }

    /**
     * Load all command configurations from the commands directory
     */
    private func loadCommands(): Unit {
        for (commandDir in CliConfig.commandDirs) {
            loadCommandUnderDir(commandDir)
        }
    }

    /**
     * Load all command configurations from the given directory
     */
    private func loadCommandUnderDir(commandDir: Path): Unit {
        this.commands.clear()

        if (!exists(commandDir)) {
            LogUtils.info("Commands directory does not exist: ${commandDir}")
            return
        }

        try {
            for (entry in Directory.readFrom(commandDir)) {
                if (!entry.isRegular()) {
                    continue
                }
                // Support two approaches to define custom commands:
                // 1. As a JSON file
                // 2. As a markdown file
                if (entry.path.extensionName == "json") {
                    let commandName = entry.path.fileNameWithoutExtension
                    if (let Some(command) <- loadCommandFromJson(entry.path)) {
                        this.addCommand(commandName, command)
                    }
                } else if (entry.path.extensionName == "md") {
                    let commandName = entry.path.fileNameWithoutExtension
                    if (let Some(command) <- loadCommandFromMd(entry.path)) {
                        this.addCommand(commandName, command)
                    }
                }
            }
        } catch (ex: Exception) {
            LogUtils.error("Failed to load commands: ${ex.message}")
            LogUtils.error(ex)
        }
    }

    private func addCommand(name: String, command: CustomCommand): Unit {
        // Check for conflicts with built-in commands
        if (isBuiltinCommand(name)) {
            LogUtils.info("Custom command '${name}' conflicts with built-in commands', skipping")
            return
        }
        if (this.commands.contains(name)) {
            LogUtils.info("Custom command '${name}' conflicts with existing commands', skipping")
            return
        }

        commands[name] = command
        CompletionListUtils.registerCompletionItem("/${name}")
        LogUtils.info("Loaded custom command: ${name}")
        LogUtils.info("  description: ${command.description}")
        LogUtils.info("  arguments: ${String.join(command.arguments, delimiter: ", ")}")
    }

    /**
     * Load a single command from JSON file
     */
    private func loadCommandFromJson(filePath: Path): Option<CustomCommand> {
        try {
            let content = readFile(filePath)
            let jsonValue = JsonValue.fromStr(content)
            let command = CustomCommand.fromJsonValue(jsonValue)

            if (command.description.isEmpty() || command.content.isEmpty()) {
                LogUtils.error("Command ${filePath}: description and content cannot be empty")
                return None
            }

            return Some(command)
        } catch (ex: Exception) {
            LogUtils.error("Failed to load command from ${filePath}: ${ex.message}")
            LogUtils.error(ex)
            return None
        }
    }

    /**
     * Load a single command from Markdown file
     */
    private func loadCommandFromMd(filePath: Path): Option<CustomCommand> {
        let (metadata, content) = loadMarkdown(filePath)
        return CustomCommand(
            description: metadata.get("description") ?? "",
            arguments: (metadata.get("arguments") ?? "").split(",") |>
                map { x => x.trimAscii() } |>
                collectArray,
            content: content
        )
    }

    protected func getCommand(name: String): Option<CustomCommand> {
        return this.commands.get(name)
    }

    /**
     * Build the full user query by replacing $ARGS in the command prompt template
     */
    protected func handleCustomCommand(customCommand: CustomCommand, args: String): String {
        let parseResult = parseArgs(args)
        var content = customCommand.content
        // Note that we need to wrap ${key} and ${value} with spaces to avoid partial replacements
        LogUtils.trace("Handle custom command")
        for ((key, value) in parseResult.options) {
            LogUtils.trace("Replace ${key} with ${value}")
            content = replaceWord(content, "\\$${key}", value)
        }
        return replaceWord(content, "\\$ARGS", parseResult.remaining)
    }

    private func replaceWord(text: String, word: String, replacement: String): String {
        // Use word boundary to avoid partial replacements
        let pattern = "(?<!\\w)${word}(?!\\w)"
        // Arguments are case-insensitive
        return Regex(pattern, [RegexFlag.MultiLine, RegexFlag.IgnoreCase]).replaceAll(text, replacement)
    }

    /**
     * List all available commands
     */
    private func listCommands(): Unit {
        if (commands.isEmpty()) {
            PrintUtils.printLine("No custom commands found")
            return
        }

        PrintUtils.printLine("📋 Available custom commands")
        for ((name, command) in commands) {
            PrintUtils.printLine("  • ${name} - ${command.description}")
        }
        PrintUtils.printLine("")
        PrintUtils.printLine("Usage: /<name> [arguments]")
    }

    /**
     * Show help for a specific command
     */
    private func showHelp(name: String): Unit {
        if (let Some(command) <- commands.get(name)) {
            PrintUtils.printLine("📖 ${name}")
            PrintUtils.printLine("Description: ${command.description}")
            PrintUtils.printLine("Usage: /${name} ${String.join(command.arguments, delimiter: " ")}")
        } else {
            PrintUtils.printLine("❌ Command '${name}' not found.")
        }
    }

    /**
     * Reload all commands
     */
    private func reloadCommands(): Unit {
        let oldSize = commands.size
        loadCommands()
        let newSize = commands.size
        PrintUtils.printProcedure("Command Reload", "✅ Reloaded ${newSize} custom commands (was ${oldSize})")
    }

    /**
     * Handle custom command input parsing and execution
     */
    public func handleCommand(input: String): Unit {
        // Check for direct /<command> format
        // /<command> args...
        let parts = input.split(" ") |>
            filter { x => !x.isEmpty() } |>
            map { x => x.trimAscii() } |>
            collectArray
        let cmdName = parts[0][1..] // Remove the leading '/'
        let args = String.join(parts[1..], delimiter: " ")

        // /cmd xxx
        if (cmdName != "cmd") {
            throw UnsupportedException("Unreachable")
        }
        if (args.isEmpty() || args == "list") {
            // /cmd or /cmd list
            listCommands()
        } else if (parts.size >= 2 && parts[1] == "help") {
            // /cmd help <name>
            if (parts.size >= 3) {
                showHelp(parts[2])
            } else {
                PrintUtils.printLine("Usage: /cmd help <command-name>")
            }
        } else if (args == "reload") {
            // /cmd reload
            reloadCommands()
        } else {
            PrintUtils.printLine("Unknown command. Available options:")
            PrintUtils.printLine("  /cmd list          - List all commands")
            PrintUtils.printLine("  /cmd help <name>   - Show command help")
            PrintUtils.printLine("  /cmd reload        - Reload commands")
            PrintUtils.printLine("  /<name> [args]     - Execute command (new)")
        }
    }

    static public func printBuiltinCommands() {
        let message = wrapBox(
            "Available Builtin Commands".withColor(Theme.PRIMARY),
            lines: BUILTIN_COMMANDS |>
                map { commandInfo: (String, String, Array<String>) =>
                    let cmd = "/${commandInfo[0]}".padEnd(15).withColor(AnsiColor.YELLOW)
                    let separator = " ║ ".withColor(Theme.MUTED)
                    let message = "- ${commandInfo[1]}".withColor(Theme.MUTED)
                    return " ${cmd}${separator}${message}"
                } |>
                collectArray,
            width: 60,
            align: Align.Center
        )
        PrintUtils.printLine(message)
    }

    /**
     * Check if input is a built-in command
     */
    protected static func isBuiltinCommand(name: String): Bool {
        for (builtin in BUILTIN_COMMANDS |> map { info => info[0] }) {
            if (name == builtin) {
                return true
            }
        }
        return false
    }
}
