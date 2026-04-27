package metis.program

public func cliRegisteredSubcliDescriptors(): Array<CliRootCommandDescriptor> {
    [
        ("gateway", "Run, inspect, and query the Gateway", true, false, ""),
        ("models", "Inspect models, providers, and model resolution", true, true, "https://docs.metis.ai/cli"),
        ("logs", "Inspect local CLI and runtime logs", true, true, "https://docs.metis.ai/cli"),
        ("docs", "Open documentation and inspect docs metadata", true, true, "https://docs.metis.ai/cli"),
        ("system", "Inspect local workspace and runtime system information", true, true, "https://docs.metis.ai/cli"),
        ("approvals", "Inspect approval status and policy surfaces", true, true, "https://docs.metis.ai/cli"),
        ("sandbox", "Inspect sandbox mode and sandbox policy", true, true, "https://docs.metis.ai/cli"),
        ("node", "Inspect one node and its policy state", true, true, "https://docs.metis.ai/cli"),
        ("qa", "Inspect QA status and quick checks", true, true, "https://docs.metis.ai/cli"),
        ("hooks", "Inspect hook registration and runbook metadata", true, true, "https://docs.metis.ai/cli"),
        ("webhooks", "Inspect webhook deliveries and webhook endpoints", true, true, "https://docs.metis.ai/cli"),
        ("qr", "Inspect QR handoff and pairing payloads", true, true, "https://docs.metis.ai/cli"),
        ("pairing", "Inspect pairing state and pairing handoff", true, true, "https://docs.metis.ai/cli"),
        ("daemon", "Inspect daemon state and daemon restart hints", true, true, "https://docs.metis.ai/cli"),
        ("acp", "Inspect ACP runtime metadata", true, true, "https://docs.metis.ai/cli"),
        ("nodes", "Inspect node scheduling and node policy", true, true, "https://docs.metis.ai/cli"),
        ("devices", "Inspect device state and device policy", true, true, "https://docs.metis.ai/cli"),
        ("channel", "Gateway channel operations", true, false, ""),
        ("channels", "Gateway channel operations", true, false, ""),
        ("plugin", "Gateway plugin operations", true, false, ""),
        ("plugins", "Gateway plugin operations", true, false, ""),
        ("sessions", "Gateway session operations", true, false, ""),
        ("subagents", "Gateway background subagent operations", true, false, ""),
        ("cron", "Gateway scheduler operations", true, false, "")
    ]
}
