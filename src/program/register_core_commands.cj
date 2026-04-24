package metis.program

import std.collection.ArrayList

public func cliCoreRootCommandDescriptors(): Array<CliRootCommandDescriptor> {
    let out = ArrayList<CliRootCommandDescriptor>()
    for (command in cliInteractiveRootCommandDescriptors()) {
        out.add(command)
    }
    for (command in cliMaintenanceRootCommandDescriptors()) {
        out.add(command)
    }
    for (command in cliRuntimeRootCommandDescriptors()) {
        out.add(command)
    }
    out.toArray()
}
