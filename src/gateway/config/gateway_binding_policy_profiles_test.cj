package metis.gateway.config

import magic.jsonable.*

import std.collection.HashMap
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private func bindingPolicyBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
}

private func bindingPolicyInt(obj: JsonObject, key: String): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asInt().getValue() } catch (_e: Exception) { 0 }
        case None => 0
    }
}

private func bindingPolicyString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
}

@Test
public class GatewayBindingPolicyProfilesTest {
    @TestCase
    public func summaryJsonAggregatesActionsPolicyAndConstraints(): Unit {
        let row = JsonObject(HashMap<String, JsonValue>())
        row.put("policyState", JsonString("configured"))
        row.put("actionsNeeded", true.toJsonValue())
        let actions = JsonArray([])
        actions.add(JsonString("inspect"))
        row.put("actions", actions)
        let constraints = JsonArray([])
        let constraint = JsonObject(HashMap<String, JsonValue>())
        constraint.put("satisfied", false.toJsonValue())
        constraints.add(constraint)
        row.put("constraints", constraints)
        let rows = JsonArray([])
        rows.add(row)

        let summary = gatewayBindingsPolicySummaryJson(rows)
        @Expect(bindingPolicyInt(summary, "actionsNeeded"), 1)
        @Expect(bindingPolicyString(summary, "policyState"), "remediation-required")
        @Expect(bindingPolicyString(summary, "remediationState"), "binding-review")
    }
}
