package metis.program

public func cliRunProgramHooks(ctx: CliProgramContext): Option<Int64> {
    cliRunProgramPreaction(ctx)
}
