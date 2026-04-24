package metis.program

import metis.core.config.CliConfig
import metis.io.PrintUtils

import std.collection.ArrayList

public func firstNonFlagToken(args: Array<String>): Option<(Int64, String)> {
    var idx: Int64 = 0
    while (idx < args.size) {
        let token = args[idx].trimAscii()
        if (!token.isEmpty() && !token.startsWith("-")) {
            return Some((idx, token))
        }
        idx += 1
    }
    None
}

public func cliRootCommand(args: Array<String>): Option<String> {
    match (firstNonFlagToken(args)) {
        case Some((_, token)) => Some(token.trimAscii().toAsciiLower())
        case None => None
    }
}

public func cliHasLeadingRootCommand(args: Array<String>): Bool {
    if (args.isEmpty()) {
        return false
    }
    let token = args[0].trimAscii()
    !token.isEmpty() && !token.startsWith("-")
}

public func cliArgsWithoutRootCommand(args: Array<String>): Array<String> {
    match (firstNonFlagToken(args)) {
        case Some((idx, _)) =>
            let list = ArrayList<String>()
            var i: Int64 = 0
            while (i < args.size) {
                if (i != idx) {
                    list.add(args[i])
                }
                i += 1
            }
            list.toArray()
        case None => args
    }
}

public func cliIsRootHelpInvocation(args: Array<String>): Bool {
    if (args.size == 0) {
        return false
    }
    if (args.size == 1) {
        let token = args[0].trimAscii().toAsciiLower()
        return token == "help" || token == "--help" || token == "-h"
    }
    false
}

public func cliIsRootVersionInvocation(args: Array<String>): Bool {
    if (args.size == 0) {
        return false
    }
    if (args.size == 1) {
        let token = args[0].trimAscii().toAsciiLower()
        return token == "version" || token == "--version" || token == "-v"
    }
    false
}

public func cliIsInteractiveRootCommand(cmd: String): Bool {
    let low = cmd.trimAscii().toAsciiLower()
    low == "interactive" || low == "tui" || low == "chat" || low == "setup" || low == "onboard" || low == "configure"
}

private func cliRootCommandHelpSubtitle(command: String): String {
    let cmd = command.trimAscii().toAsciiLower()
    if (
        cmd == "interactive" ||
        cmd == "tui" ||
        cmd == "chat" ||
        cmd == "setup" ||
        cmd == "onboard" ||
        cmd == "configure"
    ) {
        return "Interactive setup and chat workflow"
    }
    if (cmd == "config") {
        return "Inspect and manage local configuration"
    }
    if (cmd == "backup") {
        return "Inspect backup targets and backup state"
    }
    if (cmd == "reset") {
        return "Preview reset scope and reset targets"
    }
    if (cmd == "uninstall") {
        return "Preview local uninstall scope"
    }
    if (cmd == "message") {
        return "Send or preview one explicit CLI message turn"
    }
    if (cmd == "status" || cmd == "health" || cmd == "doctor" || cmd == "dashboard") {
        return "Inspect runtime health and local service state"
    }
    if (cmd == "agent" || cmd == "agents") {
        return "Run and inspect agent-facing workflows"
    }
    if (cmd == "mcp") {
        return "Manage MCP servers and expose the unified Gateway main runtime over MCP stdio"
    }
    if (cmd == "tasks") {
        return "Inspect and operate task workflows"
    }
    if (cmd == "models") {
        return "Inspect models, providers, and model resolution"
    }
    if (cmd == "logs") {
        return "Inspect local CLI and runtime logs"
    }
    if (cmd == "docs") {
        return "Open documentation and inspect docs metadata"
    }
    if (cmd == "system") {
        return "Inspect workspace paths, environment, and local state"
    }
    if (cmd == "approvals") {
        return "Inspect approval status and policy surfaces"
    }
    if (cmd == "sandbox") {
        return "Inspect sandbox mode and sandbox policy"
    }
    if (cmd == "node") {
        return "Inspect a single node surface"
    }
    if (cmd == "qa") {
        return "Inspect QA scripts and QA workflow metadata"
    }
    if (cmd == "hooks") {
        return "Inspect hook registration and runbook metadata"
    }
    if (cmd == "webhooks") {
        return "Inspect webhook deliveries and webhook endpoints"
    }
    if (cmd == "qr") {
        return "Inspect QR handoff and pairing payloads"
    }
    if (cmd == "pairing") {
        return "Inspect pairing state and pairing handoff"
    }
    if (cmd == "daemon") {
        return "Inspect daemon state and daemon restart hints"
    }
    if (cmd == "acp") {
        return "Inspect ACP runtime metadata"
    }
    if (cmd == "nodes") {
        return "Inspect node scheduling and node policy"
    }
    if (cmd == "devices") {
        return "Inspect device state and device policy"
    }
    if (cmd == "help") {
        return "Show root command help"
    }
    if (cmd == "version") {
        return "Show the CLI version"
    }
    "CLI command"
}

private func printRootCommandLocalHelp(command: String): Unit {
    let cmd = command.trimAscii().toAsciiLower()
    let subtitle = cliRootCommandHelpSubtitle(cmd)
    PrintUtils.printLine("Metis ${cmd}")
    PrintUtils.printLine(subtitle)
    PrintUtils.printLine("")
    printHelpSection("Usage:")
    for (line in cliRootCommandUsageLines(cmd)) {
        PrintUtils.printLine(line)
    }
    PrintUtils.printLine("")
    printHelpSection("Examples:")
    for ((exampleCmd, description) in cliRootCommandExamples(cmd)) {
        printHelpExample(exampleCmd, description)
    }
    PrintUtils.printLine("")
    PrintUtils.printLine("Docs: ${cliRootCommandDocsUrl(cmd)}")
}

private func cliShowInRootHelp(command: String): Bool {
    let cmd = command.trimAscii().toAsciiLower()
    cmd != "channel" &&
    cmd != "channels" &&
    cmd != "plugin" &&
    cmd != "plugins" &&
    cmd != "sessions" &&
    cmd != "cron"
}

public func printRegisteredRootCommandHelp(command: String): Bool {
    let cmd = command.trimAscii().toAsciiLower()
    if (cliRootCommandSupportsLocalHelp(cmd)) {
        printRootCommandLocalHelp(cmd)
        return true
    }
    if (cmd == "help") {
        printRootHelp()
        return true
    }
    false
}

public func printRootHelp(): Unit {
    PrintUtils.printLine("Metis ${CliConfig.version}")
    PrintUtils.printLine("")
    printHelpSection("Usage:")
    PrintUtils.printLine("  metis [options]")
    PrintUtils.printLine("  metis <command> [subcommand] [options]")
    PrintUtils.printLine("")
    printHelpSection("Commands:")
    PrintUtils.printLine("  Hint: commands suffixed with ... have subcommands. Run metis help <command> for details.")
    for ((name, description, hasSubcommands, _, _) in cliRootCommandDescriptors()) {
        if (!cliShowInRootHelp(name)) {
            continue
        }
        let label = if (hasSubcommands) {
            "${name} ..."
        } else {
            name
        }
        printHelpKeyValue(label, description)
    }
    PrintUtils.printLine("  Gateway aliases       channels | plugins | sessions | cron")
    PrintUtils.printLine("")
    printHelpSection("Options:")
    printHelpKeyValue("--model <model>", "Set the chat model")
    printHelpKeyValue("--prompt <prompt>", "Compatibility single-turn entrypoint via the unified Gateway main runtime; prefer `agent --message`")
    printHelpKeyValue("--prompt-file <file>", "Read one compatibility single-turn prompt from file and send it through the unified Gateway main runtime")
    printHelpKeyValue("--output-format <fmt>", "Set non-interactive output: plain | colorful")
    printHelpKeyValue("--sandbox", "Run inside sandbox mode")
    printHelpKeyValue("--version, -v", "Print the version")
    printHelpKeyValue("--help, -h", "Display help")
    PrintUtils.printLine("")
    printHelpSection("Examples:")
    printHelpExample("metis interactive", "Start the interactive shell through the unified Gateway main runtime.")
    printHelpExample("metis agent --message \"Summarize this repo\"", "Run one formal agent turn.")
    printHelpExample("metis --prompt \"Summarize this repo\"", "Compatibility single-turn entrypoint; prefer `agent --message`.")
    printHelpExample("metis gateway --help", "Show gateway command help.")
    PrintUtils.printLine("")
    PrintUtils.printLine("Docs: https://docs.metis.ai/cli")
}
