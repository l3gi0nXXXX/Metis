package metis.program

public func cliMaintenanceRootCommandDescriptors(): Array<CliRootCommandDescriptor> {
    [
        ("config", "Inspect and manage local configuration", true, true, "https://docs.metis.ai/cli/config"),
        ("backup", "Backup local CLI state and settings", true, true, "https://docs.metis.ai/cli"),
        ("reset", "Reset selected local CLI state", true, true, "https://docs.metis.ai/cli"),
        ("uninstall", "Remove local CLI state and generated files", true, true, "https://docs.metis.ai/cli"),
        ("message", "Preview and inspect explicit message payloads and message-side helpers", true, true, "https://docs.metis.ai/cli"),
        ("help", "Display root help", false, true, "https://docs.metis.ai/cli"),
        ("version", "Print the CLI version", false, true, "https://docs.metis.ai/cli")
    ]
}
