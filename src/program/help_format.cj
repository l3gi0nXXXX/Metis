package metis.program

import metis.io.PrintUtils

private func padRightText(text: String, width: Int64): String {
    let missing = width - text.size
    if (missing <= 0) {
        return text
    }
    text + " " * missing
}

public func printHelpSection(title: String): Unit {
    PrintUtils.printLine(title)
}

public func printHelpKeyValue(left: String, right: String, width!: Int64 = 20): Unit {
    PrintUtils.printLine("  ${padRightText(left, width)} ${right}")
}

public func printHelpExample(cmd: String, desc: String): Unit {
    PrintUtils.printLine("  ${cmd}")
    if (!desc.trimAscii().isEmpty()) {
        PrintUtils.printLine("    ${desc}")
    }
}
