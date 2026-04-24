package metis.program

public func cliInteractiveRootCommandDescriptors(): Array<CliRootCommandDescriptor> {
    [
        ("setup", "Initialize local config and CLI workspace", false, true, "https://docs.metis.ai/cli/tui"),
        ("onboard", "Interactive onboarding for gateway, workspace, and skills", false, true, "https://docs.metis.ai/cli/tui"),
        ("configure", "Interactive configuration for credentials and defaults", false, true, "https://docs.metis.ai/cli/tui"),
        ("interactive", "Start the interactive shell that routes turns through the unified Gateway main runtime", false, true, "https://docs.metis.ai/cli/tui"),
        ("tui", "Alias for interactive shell", false, true, "https://docs.metis.ai/cli/tui"),
        ("chat", "Alias for interactive shell", false, true, "https://docs.metis.ai/cli/tui")
    ]
}
