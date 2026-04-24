package metis.program

public func cliDispatchProgramFastPath(ctx: CliProgramContext): Option<Int64> {
    if (let Some(code) <- cliRunProgramHooks(ctx)) {
        return Some(code)
    }
    if (let Some(code) <- cliDispatchRegisteredRootCommand(ctx.rawArgs)) {
        return Some(code)
    }
    match (ctx.rootCommand) {
        case Some(command) =>
            if (!ctx.interactiveRootCommand && cliHasLeadingRootCommand(ctx.rawArgs)) {
                return Some(cliReturnUnknownRootCommand(command))
            }
            None
        case None => None
    }
}

public func cliProgramShouldEnterInteractive(ctx: CliProgramContext): Bool {
    ctx.interactiveRootCommand
}

public func cliProgramInteractiveMode(ctx: CliProgramContext): String {
    ctx.interactiveMode
}

public func cliProgramCommandArgs(ctx: CliProgramContext): Array<String> {
    ctx.commandArgs
}
