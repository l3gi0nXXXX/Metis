package metis.program

import metis.io.PrintUtils

public const CLI_EXIT_OK: Int64 = 0
public const CLI_EXIT_USAGE_ERROR: Int64 = 1

public func cliReturnOk(): Int64 {
    CLI_EXIT_OK
}

public func cliReturnUsageError(message: String): Int64 {
    PrintUtils.printLine(message)
    CLI_EXIT_USAGE_ERROR
}

public func cliReturnUnknownRootCommand(command: String): Int64 {
    PrintUtils.printLine("Unknown command: ${command}")
    PrintUtils.printLine("Try: metis help")
    PrintUtils.printLine("")
    printRootHelp()
    CLI_EXIT_USAGE_ERROR
}

public func cliReturnUnknownHelpTarget(command: String): Int64 {
    PrintUtils.printLine("Unknown command: ${command}")
    PrintUtils.printLine("Try: metis help")
    PrintUtils.printLine("")
    printRootHelp()
    CLI_EXIT_USAGE_ERROR
}

public func cliReturnUnknownSubcommand(command: String, sub: String, supported: String): Int64 {
    PrintUtils.printLine("Unknown ${command} subcommand: ${sub}")
    PrintUtils.printLine("Try: metis ${command} help")
    PrintUtils.printLine("Try: metis help ${command}")
    PrintUtils.printLine("Supported subcommands: ${supported}")
    CLI_EXIT_USAGE_ERROR
}

public func cliReturnMissingArgument(command: String, sub: String, expected: String): Int64 {
    PrintUtils.printLine("Missing required argument for ${command} ${sub}: ${expected}")
    PrintUtils.printLine("Try: metis ${command} help")
    PrintUtils.printLine("Try: metis help ${command}")
    CLI_EXIT_USAGE_ERROR
}

public func cliReturnInvalidArgument(command: String, sub: String, value: String, expected: String): Int64 {
    PrintUtils.printLine("Invalid argument for ${command} ${sub}: ${value}")
    PrintUtils.printLine("Expected: ${expected}")
    PrintUtils.printLine("Try: metis ${command} help")
    PrintUtils.printLine("Try: metis help ${command}")
    CLI_EXIT_USAGE_ERROR
}
