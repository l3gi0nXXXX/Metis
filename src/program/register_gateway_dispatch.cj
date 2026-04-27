package metis.program

import metis.gateway.runtime.{runGatewayCli, runGatewayDashboardCli}

import std.collection.ArrayList

private func appendHead(head: String, tail: Array<String>): Array<String> {
    let out = ArrayList<String>()
    out.add(head)
    for (item in tail) {
        out.add(item)
    }
    out.toArray()
}

public func cliDispatchGatewayBackedRootCommand(cmd: String, tail: Array<String>): Option<Int64> {
    let command = cmd.trimAscii().toAsciiLower()
    if (command == "status") {
        return Some(runGatewayCli(["status"]))
    }
    if (command == "health") {
        return Some(runGatewayCli(["health"]))
    }
    if (command == "doctor") {
        return Some(runGatewayCli(["call", "doctor.remediation"]))
    }
    if (command == "dashboard") {
        return Some(runGatewayDashboardCli(tail))
    }
    if (command == "gateway") {
        return Some(runGatewayCli(tail))
    }
    if (command == "channel" || command == "channels") {
        return Some(runGatewayCli(appendHead("channel", tail)))
    }
    if (command == "plugin" || command == "plugins") {
        return Some(runGatewayCli(appendHead("plugin", tail)))
    }
    if (command == "sessions" || command == "cron" || command == "subagents") {
        return Some(runGatewayCli(appendHead(command, tail)))
    }
    None
}
