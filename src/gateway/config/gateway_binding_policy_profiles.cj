package metis.gateway.config

import magic.jsonable.*

import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

private func gatewayBindingPolicyCount(obj: JsonObject, key: String): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asInt().getValue() } catch (_e: Exception) { 0 }
        case None => 0
    }
}

public func gatewayBindingsPolicySummaryJson(bindings: JsonArray): JsonObject {
    let summary = JsonObject()
    let byPolicyState = JsonObject()
    let actions = JsonArray([])
    var actionsNeeded: Int64 = 0
    var constrained: Int64 = 0
    for (i in 0..bindings.size()) {
        let row = try { bindings[i].asObject() } catch (_e: Exception) { JsonObject() }
        let policyState = match (row.get("policyState")) {
            case Some(v) =>
                try { v.asString().getValue().trimAscii() } catch (_e2: Exception) { "unknown" }
            case None => "unknown"
        }
        let current = gatewayBindingPolicyCount(byPolicyState, policyState)
        byPolicyState.put(policyState, (current + 1).toJsonValue())
        let rowNeedsActions = match (row.get("actionsNeeded")) {
            case Some(v) =>
                try { v.asBool().getValue() } catch (_e2: Exception) { false }
            case None => false
        }
        if (rowNeedsActions) {
            actionsNeeded += 1
        }
        let rowActions = match (row.get("actions")) {
            case Some(v) =>
                try { v.asArray() } catch (_e2: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        for (j in 0..rowActions.size()) {
            actions.add(rowActions[j])
        }
        let constraints = match (row.get("constraints")) {
            case Some(v) =>
                try { v.asArray() } catch (_e2: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        for (j in 0..constraints.size()) {
            let c = try { constraints[j].asObject() } catch (_e3: Exception) { JsonObject() }
            let satisfied = match (c.get("satisfied")) {
                case Some(v) =>
                    try { v.asBool().getValue() } catch (_e4: Exception) { true }
                case None => true
            }
            if (!satisfied) {
                constrained += 1
            }
        }
    }
    summary.put("count", bindings.size().toJsonValue())
    summary.put("actionsNeeded", actionsNeeded.toJsonValue())
    summary.put("constrained", constrained.toJsonValue())
    summary.put("byPolicyState", byPolicyState)
    summary.put("actions", actions)
    summary.put("actionCount", actions.size().toJsonValue())
    summary.put("policyState", JsonString(if (actionsNeeded == 0) { "steady" } else { "remediation-required" }))
    summary.put("remediationState", JsonString(if (actionsNeeded == 0) { "ready" } else { "binding-review" }))
    summary
}
