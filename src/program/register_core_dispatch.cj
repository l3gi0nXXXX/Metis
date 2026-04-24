package metis.program

public func cliDispatchCoreRootCommand(cmd: String, tail: Array<String>): Option<Int64> {
    let command = cmd.trimAscii().toAsciiLower()
    if (command == "config") {
        return Some(cliRunConfigFlow(tail))
    }
    if (command == "backup") {
        return Some(cliRunBackupFlow(tail))
    }
    if (command == "reset") {
        return Some(cliRunResetFlow(tail))
    }
    if (command == "uninstall") {
        return Some(cliRunUninstallFlow(tail))
    }
    if (command == "message") {
        return Some(cliRunMessageFlow(tail))
    }
    if (command == "tasks") {
        return Some(cliRunTasksFlow(tail))
    }
    if (command == "models") {
        return Some(cliRunModelsFlow(tail))
    }
    if (command == "logs") {
        return Some(cliRunLogsFlow(tail))
    }
    if (command == "docs") {
        return Some(cliRunDocsFlow(tail))
    }
    if (command == "system") {
        return Some(cliRunSystemFlow(tail))
    }
    if (command == "approvals") {
        return Some(cliRunApprovalsFlow(tail))
    }
    if (command == "sandbox") {
        return Some(cliRunSandboxFlow(tail))
    }
    if (command == "node") {
        return Some(cliRunNodeFlow(tail))
    }
    if (command == "qa") {
        return Some(cliRunQaFlow(tail))
    }
    if (command == "hooks") {
        return Some(cliRunHooksFlow(tail))
    }
    if (command == "webhooks") {
        return Some(cliRunWebhooksFlow(tail))
    }
    if (command == "qr") {
        return Some(cliRunQrFlow(tail))
    }
    if (command == "pairing") {
        return Some(cliRunPairingFlow(tail))
    }
    if (command == "daemon") {
        return Some(cliRunDaemonFlow(tail))
    }
    if (command == "acp") {
        return Some(cliRunAcpFlow(tail))
    }
    if (command == "nodes") {
        return Some(cliRunNodesFlow(tail))
    }
    if (command == "devices") {
        return Some(cliRunDevicesFlow(tail))
    }
    if (command == "agent") {
        return Some(cliRunAgentFlow(tail))
    }
    if (command == "agents") {
        return Some(cliRunAgentsFlow(tail))
    }
    if (command == "mcp") {
        return Some(cliRunMcpFlow(tail))
    }
    None
}
