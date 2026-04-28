package metis.core

import magic.prelude.*

import metis.core.config.GatewaySubagentPolicyUserSettings

import std.fs.Path
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

public class SubagentPolicyDecision {
    public var allowed: Bool = true
    public var status: String = "allowed"
    public var reason: String = ""
    public var error: String = ""
    public var effectiveTimeoutSeconds: Int64 = -1
    public var timeoutClamped: Bool = false
    public var childAllowedTools: Array<String> = []
    public var childDeniedTools: Array<String> = []
    public var activeRunCount: Int64 = 0
    public var staleRunCount: Int64 = 0
    public var recordedRunCount: Int64 = 0
    public var terminalRunCount: Int64 = 0
    public init() {}
}

private func subagentPolicyJsonArray(values: Array<String>): JsonArray {
    let arr = JsonArray([])
    for (value in values) {
        arr.add(JsonString(value.trimAscii()))
    }
    arr
}

private func subagentPolicyStringArrayContains(values: Array<String>, target: String): Bool {
    let normalizedTarget = target.trimAscii().toAsciiLower()
    for (value in values) {
        let normalized = value.trimAscii().toAsciiLower()
        if (normalized == "*" || normalized == normalizedTarget) {
            return true
        }
    }
    false
}

private func subagentPolicyRejected(reason: String, effectiveTimeoutSeconds: Int64, settings: GatewaySubagentPolicyUserSettings): SubagentPolicyDecision {
    let decision = SubagentPolicyDecision()
    decision.allowed = false
    decision.status = "rejected"
    decision.reason = reason
    decision.error = "subagent policy rejected: ${reason}"
    decision.effectiveTimeoutSeconds = effectiveTimeoutSeconds
    decision.childAllowedTools = settings.childAllowedTools
    decision.childDeniedTools = settings.childDeniedTools
    decision
}

private func subagentPolicyAllowed(effectiveTimeoutSeconds: Int64, timeoutClamped: Bool, settings: GatewaySubagentPolicyUserSettings): SubagentPolicyDecision {
    let decision = SubagentPolicyDecision()
    decision.allowed = true
    decision.status = "allowed"
    decision.reason = "allowed"
    decision.effectiveTimeoutSeconds = effectiveTimeoutSeconds
    decision.timeoutClamped = timeoutClamped
    decision.childAllowedTools = settings.childAllowedTools
    decision.childDeniedTools = settings.childDeniedTools
    decision
}

private func subagentPolicyStatusIsActive(status: String): Bool {
    match (status.trimAscii().toAsciiLower()) {
        case "queued" | "running" => true
        case _ => false
    }
}

public func gatewaySubagentPolicyDecisionToJson(decision: SubagentPolicyDecision): JsonObject {
    let obj = JsonObject()
    obj.put("allowed", decision.allowed.toJsonValue())
    obj.put("status", JsonString(decision.status))
    obj.put("reason", JsonString(decision.reason))
    obj.put("error", JsonString(decision.error))
    obj.put("effectiveTimeoutSeconds", decision.effectiveTimeoutSeconds.toJsonValue())
    obj.put("timeoutClamped", decision.timeoutClamped.toJsonValue())
    obj.put("childAllowedTools", subagentPolicyJsonArray(decision.childAllowedTools))
    obj.put("childDeniedTools", subagentPolicyJsonArray(decision.childDeniedTools))
    obj.put("activeRunCount", decision.activeRunCount.toJsonValue())
    obj.put("staleRunCount", decision.staleRunCount.toJsonValue())
    obj.put("recordedRunCount", decision.recordedRunCount.toJsonValue())
    obj.put("terminalRunCount", decision.terminalRunCount.toJsonValue())
    return obj
}

public func gatewaySubagentPolicyRejectionJson(decision: SubagentPolicyDecision, agentId: String, runtime: String): JsonObject {
    let obj = JsonObject()
    obj.put("ok", false.toJsonValue())
    obj.put("status", JsonString("rejected"))
    obj.put("error", JsonString(decision.error))
    obj.put("reason", JsonString(decision.reason))
    obj.put("agentId", JsonString(agentId.trimAscii()))
    obj.put("runtime", JsonString(runtime.trimAscii()))
    obj.put("policy", gatewaySubagentPolicyDecisionToJson(decision))
    return obj
}

public func gatewaySubagentEvaluateSpawnPolicy(
    settings: GatewaySubagentPolicyUserSettings,
    sessionsRoot: Path,
    requesterSessionKey: String,
    agentId: String,
    agentSource: String,
    runtime: String,
    requestedTimeoutSeconds: Int64,
    currentDepth: Int64,
    requestedIsolationMode: String,
    activeRunCountOverride!: Int64 = -1,
    staleRunCountOverride!: Int64 = -1,
    recordedRunCountOverride!: Int64 = -1,
    terminalRunCountOverride!: Int64 = -1
): SubagentPolicyDecision {
    var effectiveTimeoutSeconds = requestedTimeoutSeconds
    if (effectiveTimeoutSeconds < 0) {
        effectiveTimeoutSeconds = settings.defaultTimeoutSeconds
    }
    var timeoutClamped = false
    if (settings.maxTimeoutSeconds >= 0 && effectiveTimeoutSeconds > settings.maxTimeoutSeconds) {
        effectiveTimeoutSeconds = settings.maxTimeoutSeconds
        timeoutClamped = true
    }

    let cleanAgentId = agentId.trimAscii()
    let cleanAgentSource = agentSource.trimAscii().toAsciiLower()
    let cleanIsolationMode = requestedIsolationMode.trimAscii().toAsciiLower()

    if (!settings.enabled) {
        return subagentPolicyRejected("subagents disabled", effectiveTimeoutSeconds, settings)
    }
    if (settings.requireAgentId && cleanAgentId.isEmpty()) {
        return subagentPolicyRejected("agent id required", effectiveTimeoutSeconds, settings)
    }
    if (subagentPolicyStringArrayContains(settings.denyAgents, cleanAgentId)) {
        return subagentPolicyRejected("agent denied: ${cleanAgentId}", effectiveTimeoutSeconds, settings)
    }
    if (settings.allowAgents.size > 0 && !subagentPolicyStringArrayContains(settings.allowAgents, cleanAgentId)) {
        return subagentPolicyRejected("agent not allowed: ${cleanAgentId}", effectiveTimeoutSeconds, settings)
    }
    if (!settings.allowCustomAgents && cleanAgentSource == "custom") {
        return subagentPolicyRejected("custom agents disabled", effectiveTimeoutSeconds, settings)
    }
    if (!settings.allowWriteAgents && gatewaySubagentAgentLooksWriteCapable(cleanAgentId)) {
        return subagentPolicyRejected("write-capable agents disabled: ${cleanAgentId}", effectiveTimeoutSeconds, settings)
    }
    if (settings.requireWorktreeForWriteAgents &&
        gatewaySubagentAgentLooksWriteCapable(cleanAgentId) &&
        cleanIsolationMode != "worktree") {
        return subagentPolicyRejected("write-capable agents require worktree isolation", effectiveTimeoutSeconds, settings)
    }
    if (settings.maxSpawnDepth >= 0 && currentDepth >= settings.maxSpawnDepth) {
        return subagentPolicyRejected("max spawn depth exceeded", effectiveTimeoutSeconds, settings)
    }

    let records = gatewaySubagentListRunRecords(sessionsRoot)
    var activeRunCount = activeRunCountOverride
    var staleRunCount = staleRunCountOverride
    var recordedRunCount = recordedRunCountOverride
    var terminalRunCount = terminalRunCountOverride
    if (activeRunCount < 0) {
        activeRunCount = 0
        staleRunCount = if (staleRunCount < 0) { 0 } else { staleRunCount }
        recordedRunCount = if (recordedRunCount < 0) { 0 } else { recordedRunCount }
        terminalRunCount = if (terminalRunCount < 0) { 0 } else { terminalRunCount }
        for (record in records) {
            if (subagentPolicyStatusIsActive(gatewaySubagentRunRecordString(record, "status"))) {
                activeRunCount += 1
            } else if (gatewaySubagentRunStatusIsTerminal(gatewaySubagentRunRecordString(record, "status"))) {
                terminalRunCount += 1
            }
        }
    } else {
        if (staleRunCount < 0) { staleRunCount = 0 }
        if (recordedRunCount < 0) { recordedRunCount = 0 }
        if (terminalRunCount < 0) { terminalRunCount = 0 }
    }
    if (settings.maxConcurrentSubagents > 0) {
        if (activeRunCount >= settings.maxConcurrentSubagents) {
            let rejected = subagentPolicyRejected("max concurrent subagents exceeded", effectiveTimeoutSeconds, settings)
            rejected.activeRunCount = activeRunCount
            rejected.staleRunCount = staleRunCount
            rejected.recordedRunCount = recordedRunCount
            rejected.terminalRunCount = terminalRunCount
            return rejected
        }
    }

    let requester = requesterSessionKey.trimAscii()
    if (!requester.isEmpty() && settings.maxChildrenPerSession > 0) {
        var children: Int64 = 0
        for (record in records) {
            if (gatewaySubagentRunRecordString(record, "requesterSessionKey") == requester ||
                gatewaySubagentRunRecordString(record, "parentSessionKey") == requester) {
                children += 1
            }
        }
        if (children >= settings.maxChildrenPerSession) {
            let rejected = subagentPolicyRejected("max children per session exceeded", effectiveTimeoutSeconds, settings)
            rejected.activeRunCount = activeRunCount
            rejected.staleRunCount = staleRunCount
            rejected.recordedRunCount = recordedRunCount
            rejected.terminalRunCount = terminalRunCount
            return rejected
        }
    }

    let allowed = subagentPolicyAllowed(effectiveTimeoutSeconds, timeoutClamped, settings)
    allowed.activeRunCount = activeRunCount
    allowed.staleRunCount = staleRunCount
    allowed.recordedRunCount = recordedRunCount
    allowed.terminalRunCount = terminalRunCount
    return allowed
}
