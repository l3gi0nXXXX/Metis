package metis.program

import metis.core.config.CliConfig
import metis.io.PrintUtils
import metis.gateway.runtime.{gatewaySubcommandArgs, runGatewayCli}

private func tryHandleRootHelpCommand(ctx: CliProgramContext): Option<Int64> {
    if (ctx.rawArgs.size < 2 || ctx.rawArgs[0].trimAscii().toAsciiLower() != "help") {
        return None
    }
    let target = ctx.rawArgs[1].trimAscii().toAsciiLower()
    if (printRegisteredRootCommandHelp(target)) {
        return Some(0)
    }
    if (target == "gateway") {
        return Some(runGatewayCli(["--help"]))
    }
    if (target == "channel" || target == "channels") {
        return Some(runGatewayCli(["channel", "list"]))
    }
    if (target == "plugin" || target == "plugins") {
        return Some(runGatewayCli(["plugin", "list"]))
    }
    if (target == "sessions" || target == "cron") {
        return Some(runGatewayCli([target, "help"]))
    }
    Some(cliReturnUnknownHelpTarget(target))
}

public func cliRunProgramPreaction(ctx: CliProgramContext): Option<Int64> {
    if (ctx.rawArgs.isEmpty()) {
        printRootHelp()
        return Some(0)
    }
    if (let Some(gwArgs) <- gatewaySubcommandArgs(ctx.rawArgs)) {
        return Some(runGatewayCli(gwArgs))
    }
    if (cliIsRootHelpInvocation(ctx.rawArgs)) {
        printRootHelp()
        return Some(0)
    }
    if (cliIsRootVersionInvocation(ctx.rawArgs)) {
        PrintUtils.printLine(CliConfig.version)
        return Some(0)
    }
    tryHandleRootHelpCommand(ctx)
}
