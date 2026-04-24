package metis.program

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
    let cmd = command.trimAscii().toAsciiLower()
    if (
        cmd == "interactive" ||
        cmd == "tui" ||
        cmd == "chat" ||
        cmd == "setup" ||
        cmd == "onboard" ||
        cmd == "configure"
    ) {
        return [
            ("metis interactive", "Start the interactive shell that routes turns through the unified Gateway main runtime."),
            ("metis onboard", "Run onboarding in interactive mode.")
        ]
    }
    if (cmd == "config") {
        return [
            ("metis configure", "Open interactive configuration."),
            ("metis config validate", "Validate local configuration state.")
        ]
    }
    if (cmd == "backup") {
        return [
            ("metis backup state", "Inspect the planned backup scope."),
            ("metis backup preview", "Preview backup output paths.")
        ]
    }
    if (cmd == "reset") {
        return [
            ("metis reset preview", "Preview the reset scope before applying it."),
            ("metis reset targets", "Inspect named reset targets.")
        ]
    }
    if (cmd == "uninstall") {
        return [
            ("metis uninstall preview", "Inspect what local state would be removed."),
            ("metis uninstall path", "Show the local state root.")
        ]
    }
    if (cmd == "message") {
        return [
            ("metis message preview \"Summarize this repo\"", "Preview one explicit message payload without entering the formal agent flow."),
            ("metis message file prompt.txt", "Inspect one message payload loaded from file before handing it to the formal agent flow.")
        ]
    }
    if (cmd == "status") {
        return [("metis status", "Show local runtime and gateway status.")]
    }
    if (cmd == "health") {
        return [("metis health", "Fetch the local health summary.")]
    }
    if (cmd == "doctor") {
        return [("metis doctor", "Show remediation suggestions.")]
    }
    if (cmd == "dashboard") {
        return [("metis dashboard", "Open the Control UI with the current gateway binding and show whether bundled-root, configured static-root, or legacy inline mode is active.")]
    }
    if (cmd == "agent" || cmd == "agents") {
        return [
            ("metis agent --message \"Summarize this repo\"", "Run one formal agent turn via the unified Gateway main runtime."),
            ("metis --prompt \"Summarize this repo\"", "Compatibility single-turn entrypoint via the unified Gateway main runtime. Prefer `agent --message` for formal agent turns."),
            ("metis agent --local --message \"Summarize this repo\"", "Run one explicit embedded-only debug turn."),
            ("metis agents list", "List managed agents through the unified Gateway main runtime."),
            ("metis agents capabilities", "Inspect builtin agent capabilities."),
            ("metis agents bindings --agent reviewer", "List routing bindings for one agent."),
            ("metis agents bind --agent reviewer --bind qq:default", "Bind one route to an agent."),
            ("metis agents unbind --agent reviewer --bind qq:default", "Remove one route binding from an agent."),
            ("metis agents add --agent reviewer --name Reviewer", "Create a managed custom agent."),
            ("metis agents set-identity --agent reviewer --name Reviewer", "Update managed agent identity fields."),
            ("metis agents delete --agent reviewer", "Delete a managed custom agent.")
        ]
    }
    if (cmd == "mcp") {
        return [
            ("metis mcp serve --url ws://127.0.0.1:18788/ws", "Expose the unified Gateway main runtime as an MCP stdio bridge."),
            ("metis mcp list", "List configured MCP servers."),
            ("metis mcp show context7", "Show one configured MCP server."),
            ("metis mcp set context7 '{\"command\":\"uvx\",\"args\":[\"context7-mcp\"]}'", "Save one configured MCP server."),
            ("metis mcp unset context7", "Remove one configured MCP server.")
        ]
    }
    if (cmd == "tasks") {
        return [
            ("metis tasks list", "Inspect available task workflows."),
            ("metis tasks next", "Show the recommended next workflow.")
        ]
    }
    if (cmd == "models") {
        return [
            ("metis models status", "Inspect current model and provider state."),
            ("metis models search kimi", "Search matching models.")
        ]
    }
    if (cmd == "logs") {
        return [
            ("metis logs recent", "Inspect recent log inventory."),
            ("metis logs tail gateway.log", "Preview one log target.")
        ]
    }
    if (cmd == "docs") {
        return [
            ("metis docs open", "Open the primary CLI docs URL."),
            ("metis docs topics", "List available docs topics.")
        ]
    }
    if (cmd == "system") {
        return [
            ("metis system info", "Inspect local runtime paths."),
            ("metis system env", "Inspect CLI-related environment paths.")
        ]
    }
    if (cmd == "approvals") {
        return [
            ("metis approvals status", "Inspect approval-facing status."),
            ("metis approvals policy", "Inspect approval policy details.")
        ]
    }
    if (cmd == "sandbox") {
        return [
            ("metis sandbox status", "Inspect sandbox state."),
            ("metis sandbox rules", "List sandbox policy rules.")
        ]
    }
    if (cmd == "node") {
        return [
            ("metis node show", "Inspect the current node view."),
            ("metis node policy", "Inspect single-node policy details.")
        ]
    }
    if (cmd == "qa") {
        return [
            ("metis qa status", "Inspect QA state."),
            ("metis qa run", "List QA execution scripts.")
        ]
    }
    if (cmd == "hooks") {
        return [
            ("metis hooks status", "Inspect hook-facing status."),
            ("metis hooks runbook", "Inspect the hook runbook.")
        ]
    }
    if (cmd == "webhooks") {
        return [
            ("metis webhooks status", "Inspect webhook-facing status."),
            ("metis webhooks deliveries", "Inspect webhook deliveries.")
        ]
    }
    if (cmd == "qr") {
        return [
            ("metis qr show", "Inspect QR handoff status."),
            ("metis qr payload", "Inspect the QR payload.")
        ]
    }
    if (cmd == "pairing") {
        return [
            ("metis pairing status", "Inspect pairing state."),
            ("metis pairing current", "Inspect the current pairing session.")
        ]
    }
    if (cmd == "daemon") {
        return [
            ("metis daemon status", "Inspect daemon state."),
            ("metis daemon restart", "Inspect daemon restart actions.")
        ]
    }
    if (cmd == "acp") {
        return [
            ("metis acp status", "Inspect ACP state."),
            ("metis acp runtime", "Inspect ACP runtime metadata.")
        ]
    }
    if (cmd == "nodes") {
        return [
            ("metis nodes list", "Inspect node inventory."),
            ("metis nodes policy", "Inspect node policy details.")
        ]
    }
    if (cmd == "devices") {
        return [
            ("metis devices list", "Inspect device inventory."),
            ("metis devices audit", "Inspect device audit details.")
        ]
    }
    if (cmd == "help") {
        return [("metis help", "Show root help.")]
    }
    if (cmd == "version") {
        return [("metis --version", "Print the CLI version.")]
    }
    Array<CliRootCommandExample>()
}
