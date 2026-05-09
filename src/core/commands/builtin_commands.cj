package metis.core.commands

import metis.io.CompletionListUtils

import std.collection.ArrayList

/**
 * CLI chat slash command catalog. Keep this aligned with `process_input.cj`
 * dispatch so `/help` describes executable entries instead of stale prose.
 */
protected class BuiltinCommandInfo {
    public let name: String
    public let argsHint: String
    public let description: String
    public let subcommands: Array<String>
    public let needsGateway: Bool
    public let opensMenu: Bool

    public init(
        name: String,
        argsHint: String,
        description: String,
        subcommands: Array<String>,
        needsGateway: Bool,
        opensMenu: Bool
    ) {
        this.name = name
        this.argsHint = argsHint
        this.description = description
        this.subcommands = subcommands
        this.needsGateway = needsGateway
        this.opensMenu = opensMenu
    }
}

protected let BUILTIN_COMMANDS: ArrayList<BuiltinCommandInfo> = ArrayList([
    BuiltinCommandInfo("help", "", "Show this slash command help.", [], false, false),
    BuiltinCommandInfo("status", "", "Show CLI chat token/session usage. This is not gateway runtime status; use `metis gateway status` or `/dashboard` for that.", [], false, false),
    BuiltinCommandInfo("models", "[status|help|<provider>|<page>]", "Interactive provider/model configuration. `/models status` and provider pages are read-only.", ["status", "help", "<provider>", "<page>"], false, true),
    BuiltinCommandInfo("dashboard", "[--open|--no-open|help]", "Print/open the Control UI URL for the running gateway.", ["help", "--open", "--no-open"], true, false),
    BuiltinCommandInfo("skills", "<list|info|check|search|install|update> ...", "Skills operations.", ["list", "info", "check", "search", "install", "update"], false, false),
    BuiltinCommandInfo("Metis", "", "Legacy compatibility menu for gateway workflows. Prefer /channel, /plugin, /sessions, and /cron.", [], false, true),
    BuiltinCommandInfo("channel", "[list|help|enable|disable|set] ...", "Gateway channel operations. Bare `/channel` opens a menu.", ["list", "help", "enable <feishu|qq>", "disable <feishu|qq>", "set <feishu|qq> <key> <value...>"], true, true),
    BuiltinCommandInfo("plugin", "[list|list-supported|install|enable|disable|set|help] ...", "Gateway plugin operations. Bare `/plugin` opens a menu.", ["list", "list-supported", "install <name> [--app-id <id>] [--app-secret <secret>] [--force]", "enable <id>", "disable <id>", "set <id> <key> <value...>", "help"], false, true),
    BuiltinCommandInfo("sessions", "[path|list|show|clear|delete|remove|help] ...", "Gateway persisted session operations. Bare `/sessions` opens a menu.", ["path", "list", "show <sessionKey|fileStem>", "clear <sessionKey|fileStem>", "delete <sessionKey|fileStem>", "remove <sessionKey|fileStem>", "help"], false, true),
    BuiltinCommandInfo("subagents", "<spawn|list|status|logs|poll|kill|cleanup|steer|send|help> ...", "Gateway subagent operations through the unified Gateway main runtime.", ["spawn", "list", "status", "logs", "poll", "kill", "cleanup", "steer", "send", "help"], true, false),
    BuiltinCommandInfo("cron", "<status|list|path|add|create|update|edit|remove|rm|delete|enable|disable|run|runs|wake|help> ...", "Gateway cron operations, same surface as `gateway cron`.", ["status", "list", "path", "add", "create", "update", "edit", "remove", "rm", "delete", "enable", "disable", "run", "runs", "wake", "help"], true, false),
    BuiltinCommandInfo("clear", "", "Clear conversation history and redraw the chat screen.", [], false, false),
    BuiltinCommandInfo("compact", "", "Compact the conversation history.", [], false, false),
    BuiltinCommandInfo("memory", "[status|index|search|promote|promote-explain|rem-harness|dreaming ...]", "Inspect memory files, search/reindex memory, and promote durable memory.", ["status", "status --json", "status --fix", "status --deep", "status --index", "index", "index --force", "search", "search --query", "promote", "promote --json", "promote --include-promoted", "promote explain", "promote-explain", "rem-harness", "rem-harness --json", "rem-harness --apply", "dreaming status", "dreaming reconcile", "dreaming register", "dreaming sweep"], false, false),
    BuiltinCommandInfo("init", "", "Initialize AGENTS.md for the current project.", [], false, false),
    BuiltinCommandInfo("mcp", "<add|add-sse|remove|list> ...", "Manage MCP tools.", ["add", "add-sse", "remove", "list"], false, false),
    BuiltinCommandInfo("conversation", "<list|save|resume|remove|help> ...", "Manage local conversations.", ["list", "save", "resume", "remove", "help"], false, false),
    BuiltinCommandInfo("cmd", "<list|reload|help> ...", "Manage customized slash commands.", ["list", "reload", "help <name>"], false, false),
    BuiltinCommandInfo("agents", "", "List customized agents.", [], false, false),
    BuiltinCommandInfo("exit", "", "Exit the interactive chat.", [], false, false)
])

public func renderBuiltinCommandsHelp(): String {
    let sb = StringBuilder()
    sb.append("CLI chat slash commands\n")
    sb.append("Legend: gateway=yes requires a running Gateway runtime; menu=yes opens an interactive menu when used without arguments.\n\n")
    for (command in BUILTIN_COMMANDS) {
        let usage = if (command.argsHint.trimAscii().isEmpty()) {
            "/${command.name}"
        } else {
            "/${command.name} ${command.argsHint}"
        }
        let gateway = if (command.needsGateway) { "yes" } else { "no" }
        let menu = if (command.opensMenu) { "yes" } else { "no" }
        sb.append("${usage}\n")
        sb.append("  ${command.description}\n")
        sb.append("  gateway=${gateway}; menu=${menu}\n")
        if (!command.subcommands.isEmpty()) {
            sb.append("  args: ${String.join(command.subcommands, delimiter: " | ")}\n")
        }
    }
    sb.append("\nCustom slash commands: use `/cmd list`; skill slash commands also work when a skill name matches.\n")
    sb.toString()
}

func registerBuiltinCommands(): Unit {
    for (command in BUILTIN_COMMANDS) {
        let commandName = command.name
        // 一级入口控制：
        // - /plugin /channel /sessions /subagents 仅显示入口，不在一级补全展开子命令；
        // - /Metis 保留入口，兼容旧交互工作流。
        if (commandName != "skills") {
            CompletionListUtils.registerCompletionItem("/${commandName}")
        }

        if (commandName == "plugin" || commandName == "channel" || commandName == "sessions" || commandName == "subagents" || commandName == "cron") {
            continue
        }

        // Add subcommands if they match
        for (subcommand in command.subcommands) {
            let fullSubcommand = "/${commandName} ${subcommand}"
            CompletionListUtils.registerCompletionItem(fullSubcommand)
        }
    }
}
