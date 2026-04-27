package metis.core

import std.fs.Path

public func gatewaySubagentRuntimeState(status: String): String {
    match (status.trimAscii().toAsciiLower()) {
        case "completed" | "complete" | "success" | "ok" | "succeeded" => "succeeded"
        case "cancelling" | "canceling" | "cancelled" | "canceled" => "cancelled"
        case "timeout" | "timedout" | "timed_out" => "timed_out"
        case "running" => "running"
        case "queued" => "queued"
        case "failed" | "error" => "failed"
        case _ => "queued"
    }
}

public func gatewaySubagentRunStatusIsTerminal(status: String): Bool {
    match (gatewaySubagentRuntimeState(status)) {
        case "succeeded" | "failed" | "cancelled" | "timed_out" => true
        case _ => false
    }
}

public func gatewaySubagentMarkRunState(
    sessionsRoot: Path,
    runIdOrSessionKey: String,
    status: String,
    resultSummary!: String = "",
    error!: String = "",
    exitCode!: Int64 = 0,
    outputPath!: String = ""
): Bool {
    gatewaySubagentUpdateRunStatus(
        sessionsRoot,
        runIdOrSessionKey,
        gatewaySubagentRuntimeState(status),
        resultSummary: resultSummary,
        error: error,
        exitCode: exitCode,
        outputPath: outputPath
    )
}

public func gatewaySubagentMarkRunRunning(sessionsRoot: Path, runIdOrSessionKey: String): Bool {
    gatewaySubagentMarkRunState(sessionsRoot, runIdOrSessionKey, "running")
}

public func gatewaySubagentMarkRunSucceeded(
    sessionsRoot: Path,
    runIdOrSessionKey: String,
    resultSummary!: String = "",
    exitCode!: Int64 = 0,
    outputPath!: String = ""
): Bool {
    gatewaySubagentMarkRunState(
        sessionsRoot,
        runIdOrSessionKey,
        "succeeded",
        resultSummary: resultSummary,
        exitCode: exitCode,
        outputPath: outputPath
    )
}

public func gatewaySubagentMarkRunFailed(
    sessionsRoot: Path,
    runIdOrSessionKey: String,
    error!: String = "",
    exitCode!: Int64 = 1
): Bool {
    gatewaySubagentMarkRunState(
        sessionsRoot,
        runIdOrSessionKey,
        "failed",
        error: error,
        exitCode: exitCode
    )
}

public func gatewaySubagentMarkRunCancelled(
    sessionsRoot: Path,
    runIdOrSessionKey: String,
    reason!: String = "cancelled"
): Bool {
    gatewaySubagentMarkRunState(
        sessionsRoot,
        runIdOrSessionKey,
        "cancelled",
        error: reason,
        exitCode: -1
    )
}

public func gatewaySubagentMarkRunTimedOut(
    sessionsRoot: Path,
    runIdOrSessionKey: String,
    timeoutSeconds: Int64
): Bool {
    let detail = if (timeoutSeconds > 0) {
        "subagent timed out after ${timeoutSeconds}s"
    } else {
        "subagent timed out"
    }
    gatewaySubagentMarkRunState(
        sessionsRoot,
        runIdOrSessionKey,
        "timed_out",
        error: detail,
        exitCode: -1
    )
}
