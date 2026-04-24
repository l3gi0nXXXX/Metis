package metis.program

public struct CliProgramContext {
    CliProgramContext(
        public let rawArgs: Array<String>,
        public let rootCommand: Option<String>,
        public let commandArgs: Array<String>,
        public let interactiveRootCommand: Bool,
        public let interactiveMode: String
    ) {}
}

private func resolveCliInteractiveMode(rootCommand: Option<String>): String {
    match (rootCommand) {
        case Some(cmd) =>
            let low = cmd.trimAscii().toAsciiLower()
            if (low == "setup" || low == "onboard" || low == "configure") {
                return low
            }
            if (low == "tui" || low == "chat") {
                return low
            }
            if (low == "interactive") {
                return "interactive"
            }
            ""
        case None => ""
    }
}

public func createCliProgramContext(args: Array<String>): CliProgramContext {
    let rootCommand = cliRootCommand(args)
    let interactiveRootCommand = match (rootCommand) {
        case Some(cmd) => cliIsInteractiveRootCommand(cmd)
        case None => false
    }
    let interactiveMode = resolveCliInteractiveMode(rootCommand)
    let commandArgs = if (interactiveRootCommand) {
        cliArgsWithoutRootCommand(args)
    } else {
        args
    }
    CliProgramContext(args, rootCommand, commandArgs, interactiveRootCommand, interactiveMode)
}
