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

private func subagentPolicyAgentLooksWriteCapable(agentId: String): Bool {
    let normalized = agentId.trimAscii().toAsciiLower()
    if (normalized.isEmpty()) {
        return false
    }
    normalized.contains("write") ||
        normalized.contains("fix") ||
        normalized.contains("patch") ||
        normalized.contains("implement") ||
        normalized.contains("coder")
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
    requestedIsolationMode: String
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
    if (!settings.allowWriteAgents && subagentPolicyAgentLooksWriteCapable(cleanAgentId)) {
        return subagentPolicyRejected("write-capable agents disabled: ${cleanAgentId}", effectiveTimeoutSeconds, settings)
    }
    if (settings.requireWorktreeForWriteAgents &&
        subagentPolicyAgentLooksWriteCapable(cleanAgentId) &&
        cleanIsolationMode != "worktree") {
        return subagentPolicyRejected("write-capable agents require worktree isolation", effectiveTimeoutSeconds, settings)
    }
    if (settings.maxSpawnDepth >= 0 && currentDepth >= settings.maxSpawnDepth) {
        return subagentPolicyRejected("max spawn depth exceeded", effectiveTimeoutSeconds, settings)
    }

    let records = gatewaySubagentListRunRecords(sessionsRoot)
    if (settings.maxConcurrentSubagents > 0) {
        var active: Int64 = 0
        for (record in records) {
            if (subagentPolicyStatusIsActive(gatewaySubagentRunRecordString(record, "status"))) {
                active += 1
            }
        }
        if (active >= settings.maxConcurrentSubagents) {
            return subagentPolicyRejected("max concurrent subagents exceeded", effectiveTimeoutSeconds, settings)
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
            return subagentPolicyRejected("max children per session exceeded", effectiveTimeoutSeconds, settings)
        }
    }

    return subagentPolicyAllowed(effectiveTimeoutSeconds, timeoutClamped, settings)
}
