package metis.core

import std.fs.Path
import stdx.encoding.json.{JsonBool, JsonObject, JsonString}

public class GatewaySubagentEffectiveState {
    public let persistedStatus: String
    public let processState: String
    public let launchState: String
    public let effectiveState: String
    public let isTerminal: Bool
    public let isLive: Bool
    public let isActive: Bool
    public let isStale: Bool
    public let isRecordedOnly: Bool
    public let canKill: Bool
    public let canSteer: Bool
    public let canSend: Bool
    public let shouldNotify: Bool

    public init(
        persistedStatus!: String = "queued",
        processState!: String = "idle",
        launchState!: String = "unknown",
        effectiveState!: String = "unknown",
        isTerminal!: Bool = false,
        isLive!: Bool = false,
        isActive!: Bool = false,
        isStale!: Bool = false,
        isRecordedOnly!: Bool = false,
        canKill!: Bool = false,
        canSteer!: Bool = false,
        canSend!: Bool = false,
        shouldNotify!: Bool = false
    ) {
        this.persistedStatus = persistedStatus
        this.processState = processState
        this.launchState = launchState
        this.effectiveState = effectiveState
        this.isTerminal = isTerminal
        this.isLive = isLive
        this.isActive = isActive
        this.isStale = isStale
        this.isRecordedOnly = isRecordedOnly
        this.canKill = canKill
        this.canSteer = canSteer
        this.canSend = canSend
        this.shouldNotify = shouldNotify
    }
}

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

private func gatewaySubagentJsonBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(value) => try { value.asBool().getValue() } catch (_: Exception) { false }
        case None => false
    }
}

private func gatewaySubagentJsonObject(obj: JsonObject, key: String): Option<JsonObject> {
    match (obj.get(key)) {
        case Some(value) => try { Some<JsonObject>(value.asObject()) } catch (_: Exception) { None<JsonObject> }
        case None => None<JsonObject>
    }
}

private func gatewaySubagentNormalizeProcessState(hasLiveFuture: Bool, hasLiveProcess: Bool): String {
    if (hasLiveFuture || hasLiveProcess) { "live" } else { "idle" }
}

private func gatewaySubagentNormalizeLaunchState(raw: String): String {
    match (raw.trimAscii().toAsciiLower().replace("-", "_")) {
        case "started" | "running" | "live" => "started"
        case "not_started" | "queued" => "not_started"
        case "not_started_by_design" | "recorded" | "recorded_only" => "not_started_by_design"
        case "launch_failed" | "failed_to_launch" => "launch_failed"
        case _ => "unknown"
    }
}

private func gatewaySubagentRecordLaunchState(record: JsonObject, hasLiveFuture: Bool, hasLiveProcess: Bool, launchStateHint: String): String {
    let hinted = gatewaySubagentNormalizeLaunchState(launchStateHint)
    if (hinted != "unknown") {
        return hinted
    }
    match (gatewaySubagentJsonObject(record, "metadata")) {
        case Some(metadata) =>
            match (gatewaySubagentJsonObject(metadata, "agent")) {
                case Some(agent) =>
                    if (agent.get("background").isSome() && !gatewaySubagentJsonBool(agent, "background")) {
                        return "not_started_by_design"
                    }
                case None => ()
            }
        case None => ()
    }
    if (hasLiveFuture || hasLiveProcess || gatewaySubagentRunRecordInt(record, "startedAtMs") > 0) {
        return "started"
    }
    "not_started"
}

public func gatewaySubagentResolveEffectiveState(
    record: JsonObject,
    hasLiveFuture!: Bool = false,
    hasLiveProcess!: Bool = false,
    managedState!: String = "",
    launchStateHint!: String = ""
): GatewaySubagentEffectiveState {
    let persistedStatus = gatewaySubagentRuntimeState(gatewaySubagentRunRecordString(record, "status"))
    let isTerminal = gatewaySubagentRunStatusIsTerminal(persistedStatus)
    let processState = gatewaySubagentNormalizeProcessState(hasLiveFuture, hasLiveProcess)
    let isLive = processState == "live"
    let launchState = gatewaySubagentRecordLaunchState(record, hasLiveFuture, hasLiveProcess, launchStateHint)
    let isRecordedOnly = !isTerminal && launchState == "not_started_by_design"
    let effectiveState = if (isTerminal) {
        persistedStatus
    } else if (isRecordedOnly) {
        "recorded"
    } else if (isLive && persistedStatus == "running") {
        "running"
    } else if (isLive && persistedStatus == "queued") {
        "queued"
    } else if (!isLive) {
        "stale"
    } else {
        let fallback = gatewaySubagentRuntimeState(managedState)
        if (fallback == "running" || fallback == "queued") { fallback } else { "unknown" }
    }
    let isActive = effectiveState == "queued" || effectiveState == "running"
    let isStale = effectiveState == "stale"
    let canKill = !isTerminal
    let canSteer = !isTerminal && !isStale && !isRecordedOnly
    let canSend = canSteer
    let shouldNotify = isTerminal && gatewaySubagentRunRecordString(record, "noticeStatus") != "delivered"
    GatewaySubagentEffectiveState(
        persistedStatus: persistedStatus,
        processState: processState,
        launchState: launchState,
        effectiveState: effectiveState,
        isTerminal: isTerminal,
        isLive: isLive,
        isActive: isActive,
        isStale: isStale,
        isRecordedOnly: isRecordedOnly,
        canKill: canKill,
        canSteer: canSteer,
        canSend: canSend,
        shouldNotify: shouldNotify
    )
}

public func gatewaySubagentPutEffectiveState(target: JsonObject, state: GatewaySubagentEffectiveState): Unit {
    target.put("persistedStatus", JsonString(state.persistedStatus))
    target.put("processState", JsonString(state.processState))
    target.put("launchState", JsonString(state.launchState))
    target.put("effectiveState", JsonString(state.effectiveState))
    target.put("isTerminal", JsonBool(state.isTerminal))
    target.put("isLive", JsonBool(state.isLive))
    target.put("isActive", JsonBool(state.isActive))
    target.put("isStale", JsonBool(state.isStale))
    target.put("isRecordedOnly", JsonBool(state.isRecordedOnly))
    target.put("canKill", JsonBool(state.canKill))
    target.put("canSteer", JsonBool(state.canSteer))
    target.put("canSend", JsonBool(state.canSend))
    target.put("shouldNotify", JsonBool(state.shouldNotify))
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
