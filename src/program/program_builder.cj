package metis.program

import std.collection.ArrayList

public struct CliProgramDefinition {
    CliProgramDefinition(public let commands: Array<CliRootCommandDescriptor>) {}
}

public func buildCliProgram(): CliProgramDefinition {
    let commands = ArrayList<CliRootCommandDescriptor>()
    for (command in cliCoreRootCommandDescriptors()) {
        commands.add(command)
    }
    for (command in cliRegisteredSubcliDescriptors()) {
        commands.add(command)
    }
    CliProgramDefinition(commands.toArray())
}
