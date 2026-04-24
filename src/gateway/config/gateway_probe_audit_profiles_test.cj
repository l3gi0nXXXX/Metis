package metis.gateway.config

import magic.jsonable.*
import std.unittest.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

@Test
public class GatewayProbeAuditProfilesTest {
    @TestCase
    func bindingProbeAuditBundleCarriesProbeAuditAndTimestamp() {
        let bundle = gatewayBindingProbeAuditBundle(
            false,
            "pending-config",
            5000,
            JsonString("pending-config"),
            JsonString("pending-config"),
            JsonArray([]),
            JsonArray([]),
            true.toJsonValue()
        )
        let probe = bundle.get("probe").getOrThrow().asObject()
        let audit = bundle.get("audit").getOrThrow().asObject()
        @Expect(probe.get("status").getOrThrow().asString().getValue(), "pending-config")
        @Expect(probe.get("policyState").getOrThrow().asString().getValue(), "pending-config")
        @Expect(probe.get("bindingState").getOrThrow().asString().getValue(), "pending-config")
        @Expect(audit.get("remediationState").getOrThrow().asString().getValue(), "binding-review")
        @Expect(bundle.get("lastProbeAtMs").getOrThrow().asInt().getValue() >= 0, true)
    }
}
