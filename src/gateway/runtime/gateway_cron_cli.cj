package metis.gateway.runtime

import metis.cron.{executeGatewayCronCommand, formatCronHelpForTerminal, registerGatewayCronRunUnified,
    tryCronSubcommandHelpFromArgv}
import metis.io.PrintUtils

import std.sync.Mutex

private func printCronMessage(msg: String): Unit {
    let text = if (msg.contains("Usage: gateway cron")) {
        formatCronHelpForTerminal(msg)
    } else {
        msg
    }
    for (line in text.split("\n")) {
        PrintUtils.printLine(line)
    }
}

private let gatewayCronHookInitLock = Mutex()
private var gatewayCronHookInitDone: Bool = false

/** 保证 IM `/cron run` 使用的 `executeGatewayCronCommand` 钩子已绑定（无需先 `gateway serve` 也能用 CLI `gateway cron run`）。 */
private func ensureGatewayCronRunHookRegistered(): Unit {
    synchronized(gatewayCronHookInitLock) {
        if (gatewayCronHookInitDone) {
            return
        }
        registerGatewayCronRunUnified(gatewayCronRunUnified)
        gatewayCronHookInitDone = true
    }
}

/**
 * Cron 子命令分发：`run` 走 `CronRunner.runJobOnceFromStore`（与 tick 同源），其余走 `executeGatewayCronCommand`。
 */
public func gatewayExecuteCronWithUnifiedRun(sub: Array<String>): (String, Int64) {
    ensureGatewayCronRunHookRegistered()
    match (tryCronSubcommandHelpFromArgv(sub)) {
        case Some(pair) => return pair
        case None => ()
    }
    if (sub.size >= 2 && sub[1].trimAscii().toAsciiLower() == "run") {
        return gatewayCronRunUnified(sub)
    }
    executeGatewayCronCommand(sub)
}

/** `gateway cron ...` 子命令；返回退出码（与 `executeGatewayCronCommand` 一致）。 */
public func runGatewayCronCli(sub: Array<String>): Int64 {
    let (msg, code) = gatewayExecuteCronWithUnifiedRun(sub)
    printCronMessage(msg)
    code
}
