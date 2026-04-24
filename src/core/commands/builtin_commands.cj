package metis.core.commands

import metis.io.CompletionListUtils

import std.collection.ArrayList

/**
    * Command definitions: (command_name, description:  [subcommands])
    * Commands without subcommands have empty array
    */
protected let BUILTIN_COMMANDS: ArrayList<(String, String, Array<String>)> = ArrayList([
    ("models", "Configure provider and main model", []),
    ("skills", "Skills ops: list/info/check/search/install/update", ["list", "info", "check", "search", "install", "update"]),
    (
        "Metis",
        "Metis compatibility menu for legacy interactive gateway workflows. Prefer root commands or /channel, /plugin, /sessions, and /cron.",
        []
    ),
    ("channel", "Gateway channel ops: list/enable/disable/set", ["list", "enable", "disable", "set"]),
    ("plugin", "Gateway plugin ops: list/list-supported/install/enable/disable/set", ["list", "list-supported", "install", "enable", "disable", "set"]),
    ("sessions", "Gateway sessions ops: list/path/show/clear/help", ["list", "path", "show", "clear", "help"]),
    (
        "cron",
        "Gateway cron (Metis-like): path/list/add --name .../edit/remove/enable/disable",
        ["path", "list", "help", "add", "edit", "remove", "enable", "disable"]
    ),
    ("help", "Show this help message", []),
    ("clear", "Clear conversation history", []),
    ("compact", "Compact the conversation history", []),
    ("memory", "Inspect memory files, search and reindex memory, and promote durable memory", ["status", "status --json", "status --fix", "status --deep", "status --index", "index", "index --force", "search", "search --query", "promote", "promote --json", "promote --include-promoted", "promote explain", "promote-explain", "rem-harness", "rem-harness --json", "rem-harness --apply", "dreaming status", "dreaming reconcile", "dreaming register", "dreaming register light", "dreaming register rem", "dreaming register deep", "dreaming sweep", "dreaming sweep light", "dreaming sweep rem", "dreaming sweep deep"]),
    ("init", "Initialize AGENTS.md for project", []),
    ("exit", "Exit the program", []),
    ("status", "Show token status", []),
    ("mcp", "Manage MCP tools", ["add", "add-sse", "remove", "list"]),
    ("conversation", "Manage conversations", ["list", "save", "resume", "remove", "help"]),
    ("cmd", "Manage customized commands", ["list", "reload", "help"]),
    ("agents", "List all customized agents", [])
])

func registerBuiltinCommands(): Unit {
    for ((commandName, _commandDescription, subcommands) in BUILTIN_COMMANDS) {
        // 一级入口控制：
        // - /plugin /channel /sessions 仅显示入口，不在一级补全展开子命令；
        // - /Metis 保留入口，兼容旧交互工作流。
        if (commandName != "skills") {
            CompletionListUtils.registerCompletionItem("/${commandName}")
        }

        if (commandName == "plugin" || commandName == "channel" || commandName == "sessions" || commandName == "cron") {
            continue
        }

        // Add subcommands if they match
        for (subcommand in subcommands) {
            let fullSubcommand = "/${commandName} ${subcommand}"
            CompletionListUtils.registerCompletionItem(fullSubcommand)
        }
    }
}
