package metis.program

public func cliRuntimeRootCommandDescriptors(): Array<CliRootCommandDescriptor> {
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
