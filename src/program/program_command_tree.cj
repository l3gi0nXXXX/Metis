package metis.program

import metis.program_support.programSupportRootCommandExamples

import std.collection.ArrayList

public type CliRootCommandDescriptor = (String, String, Bool, Bool, String)
public type CliRootCommandExample = (String, String)

public func cliRootCommandDescriptors(): Array<CliRootCommandDescriptor> {
    buildCliProgram().commands
}

public func cliRootCommandsWithSubcommands(): Array<String> {
    let out = ArrayList<String>()
    for ((name, _, hasSubcommands, _, _) in cliRootCommandDescriptors()) {
        if (hasSubcommands) {
            out.add(name)
        }
    }
    out.toArray()
}

public func cliFindRootCommandDescriptor(command: String): Option<CliRootCommandDescriptor> {
    let cmd = command.trimAscii().toAsciiLower()
    for ((name, description, hasSubcommands, localHelp, docsUrl) in cliRootCommandDescriptors()) {
        if (name == cmd) {
            return Some((name, description, hasSubcommands, localHelp, docsUrl))
        }
    }
    None
}

public func cliRootCommandDocsUrl(command: String): String {
    match (cliFindRootCommandDescriptor(command)) {
        case Some((_, _, _, _, docsUrl)) => docsUrl
        case None => "https://docs.metis.ai/cli"
    }
}

public func cliRootCommandSupportsLocalHelp(command: String): Bool {
    match (cliFindRootCommandDescriptor(command)) {
        case Some((_, _, _, localHelp, _)) => localHelp
        case None => false
    }
}

public func cliRootCommandUsageLines(command: String): Array<String> {
    let cmd = command.trimAscii().toAsciiLower()
    if (cmd == "config") {
        return ["  metis config", "  metis config <subcommand>"]
    }
    if (cmd == "backup") {
        return ["  metis backup", "  metis backup <subcommand>"]
    }
    if (cmd == "reset") {
        return ["  metis reset", "  metis reset <subcommand>"]
    }
    if (cmd == "uninstall") {
        return ["  metis uninstall", "  metis uninstall <subcommand>"]
    }
    if (cmd == "message") {
        return ["  metis message", "  metis message <subcommand>"]
    }
    if (cmd == "agent") {
        return ["  metis agent", "  metis agent --message \"...\""]
    }
    if (cmd == "agents") {
        return ["  metis agents", "  metis agents <subcommand>"]
    }
    if (cmd == "mcp") {
        return ["  metis mcp", "  metis mcp <subcommand>"]
    }
    if (cmd == "tasks") {
        return ["  metis tasks", "  metis tasks <subcommand>"]
    }
    if (cmd == "models") {
        return ["  metis models", "  metis models <subcommand>"]
    }
    if (cmd == "logs") {
        return ["  metis logs", "  metis logs <subcommand>"]
    }
    if (cmd == "docs") {
        return ["  metis docs", "  metis docs <subcommand>"]
    }
    if (cmd == "system") {
        return ["  metis system", "  metis system <subcommand>"]
    }
    if (cmd == "approvals") {
        return ["  metis approvals", "  metis approvals <subcommand>"]
    }
    if (cmd == "sandbox") {
        return ["  metis sandbox", "  metis sandbox <subcommand>"]
    }
    if (cmd == "node") {
        return ["  metis node", "  metis node <subcommand>"]
    }
    if (cmd == "qa") {
        return ["  metis qa", "  metis qa <subcommand>"]
    }
    if (cmd == "hooks") {
        return ["  metis hooks", "  metis hooks <subcommand>"]
    }
    if (cmd == "webhooks") {
        return ["  metis webhooks", "  metis webhooks <subcommand>"]
    }
    if (cmd == "qr") {
        return ["  metis qr", "  metis qr <subcommand>"]
    }
    if (cmd == "pairing") {
        return ["  metis pairing", "  metis pairing <subcommand>"]
    }
    if (cmd == "daemon") {
        return ["  metis daemon", "  metis daemon <subcommand>"]
    }
    if (cmd == "acp") {
        return ["  metis acp", "  metis acp <subcommand>"]
    }
    if (cmd == "nodes") {
        return ["  metis nodes", "  metis nodes <subcommand>"]
    }
    if (cmd == "devices") {
        return ["  metis devices", "  metis devices <subcommand>"]
    }
    ["  metis ${cmd}"]
}

public func cliRootCommandExamples(command: String): Array<CliRootCommandExample> {
    programSupportRootCommandExamples(command)
}
