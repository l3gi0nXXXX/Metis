package metis.program_support

public type CliRootCommandDescriptor = (String, String, Bool, Bool, String)
public type CliRootCommandExample = (String, String)

public func programSupportInteractiveRootCommandDescriptors(): Array<CliRootCommandDescriptor> {
    [
        ("setup", "Initialize local config and CLI workspace", false, true, "https://docs.metis.ai/cli/tui"),
        ("onboard", "Interactive onboarding for gateway, workspace, and skills", false, true, "https://docs.metis.ai/cli/tui"),
        ("configure", "Interactive configuration for credentials and defaults", false, true, "https://docs.metis.ai/cli/tui"),
        ("interactive", "Start the interactive shell that routes turns through the unified Gateway main runtime", false, true, "https://docs.metis.ai/cli/tui"),
        ("tui", "Alias for interactive shell", false, true, "https://docs.metis.ai/cli/tui"),
        ("chat", "Alias for interactive shell", false, true, "https://docs.metis.ai/cli/tui")
    ]
}

public func programSupportRuntimeRootCommandDescriptors(): Array<CliRootCommandDescriptor> {
    [
        ("status", "Show local runtime and gateway status", false, true, "https://docs.metis.ai/cli"),
        ("health", "Fetch local health from the unified Gateway main runtime", false, true, "https://docs.metis.ai/cli"),
        ("doctor", "Health checks and remediation suggestions", false, true, "https://docs.metis.ai/cli"),
        ("dashboard", "Open the gateway Control UI and report whether bundled-root, configured static-root, or legacy inline mode is active", false, true, "https://docs.metis.ai/cli"),
        ("agent", "Run one formal agent turn via the unified Gateway main runtime", false, true, "https://docs.metis.ai/cli/agent"),
        ("agents", "Manage isolated agents, identities, and routing through the unified Gateway main runtime", true, true, "https://docs.metis.ai/cli/agent"),
        ("mcp", "Manage MCP servers and expose the unified Gateway main runtime over MCP stdio", true, true, "https://docs.metis.ai/cli/mcp"),
        ("tasks", "Inspect and operate task workflows", true, true, "https://docs.metis.ai/cli")
    ]
}

public func programSupportRootCommandExamples(command: String): Array<CliRootCommandExample> {
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
            ("metis agents bindings --agent custom-reviewer", "List routing bindings for one agent."),
            ("metis agents bind --agent custom-reviewer --bind qq:default", "Bind one route to an agent."),
            ("metis agents unbind --agent custom-reviewer --bind qq:default", "Remove one route binding from an agent."),
            ("metis agents add --agent custom-reviewer --name Reviewer", "Create a managed custom agent."),
            ("metis agents update --agent custom-reviewer --model qwen/qwen3.6-plus", "Update a managed agent model or metadata."),
            ("metis agents set-identity --agent custom-reviewer --name Reviewer", "Update managed agent identity fields."),
            ("metis agents delete --agent custom-reviewer", "Delete a managed custom agent.")
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
