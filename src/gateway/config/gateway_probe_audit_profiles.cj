package metis.gateway.config

import magic.jsonable.*

import stdx.encoding.json.{JsonObject, JsonString, JsonValue}

public func gatewayBindingAuditJson(
    ok: Bool,
    policyState: JsonValue,
    constraints: JsonValue,
    actions: JsonValue,
    actionsNeeded: JsonValue
): JsonObject {
    let audit = JsonObject()
    audit.put("policyState", policyState)
    audit.put("remediationState", JsonString(if (ok) { "ready" } else { "binding-review" }))
    audit.put("constraints", constraints)
    audit.put("actions", actions)
    audit.put("actionsNeeded", actionsNeeded)
    audit
}

public func gatewayBindingProbeAuditBundle(
    ok: Bool,
    status: String,
    timeoutMs: Int64,
    policyState: JsonValue,
    bindingState: JsonValue,
    constraints: JsonValue,
    actions: JsonValue,
    actionsNeeded: JsonValue
): JsonObject {
    let bundle = JsonObject()
    let probe = gatewayProbeResultJson(ok, status, timeoutMs)
    probe.put("policyState", policyState)
    probe.put("bindingState", bindingState)
    bundle.put("probe", probe)
    bundle.put("audit", gatewayBindingAuditJson(ok, policyState, constraints, actions, actionsNeeded))
    bundle.put("lastProbeAtMs", gatewayProbeTimestampMs().toJsonValue())
    bundle
}
