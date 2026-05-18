package metis.gateway.core

import std.convert.Parsable
import std.process.executeWithOutput

@When[os == "Windows"]
foreign {
    func GetCurrentProcessId(): UInt32
}

@When[os != "Windows"]
foreign {
    func getpid(): Int32
}

@When[os == "Windows"]
public func gatewayProcessCurrentPid(): Int64 {
    Int64(unsafe { GetCurrentProcessId() })
}

@When[os != "Windows"]
public func gatewayProcessCurrentPid(): Int64 {
    Int64(unsafe { getpid() })
}

public func gatewayProcessResidentSetKb(): Int64 {
    let pid = gatewayProcessCurrentPid()
    if (pid <= 0) {
        return -1
    }
    try {
        let (exitCode, stdout, _) = executeWithOutput("ps", ["-o", "rss=", "-p", "${pid}"])
        if (exitCode != 0) {
            return -1
        }
        let raw = String.fromUtf8(stdout).trimAscii()
        if (raw.isEmpty()) {
            return -1
        }
        let firstLine = raw.split("\n")[0].trimAscii()
        if (firstLine.isEmpty()) {
            return -1
        }
        Int64.parse(firstLine)
    } catch (_: Exception) {
        -1
    }
}

public func gatewayLogProcessMemory(scope: String, note!: String = ""): Unit {
    let pid = gatewayProcessCurrentPid()
    let rssKb = gatewayProcessResidentSetKb()
    gatewayLogEventInfo(
        "gateway/runtime",
        "process.memory",
        "gateway process memory snapshot",
        meta: gatewayLogMeta()
            .string("scope", scope)
            .int("pid", pid)
            .int("rssKb", rssKb)
            .rawString("note", note.trimAscii())
            .object()
    )
}
