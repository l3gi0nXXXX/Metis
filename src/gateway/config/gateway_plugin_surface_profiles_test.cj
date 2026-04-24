package metis.gateway.config

import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject}

private func pluginSurfaceString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

@Test
public class GatewayPluginSurfaceProfilesTest {
    @TestCase
    public func approvalSummaryAggregatesReviewState() {
        let rows = JsonArray([])
        rows.add(gatewayPluginApprovalRowJson("dingtalk", true, true, true, false))
        let result = gatewayPluginsApprovalSummaryJson(rows)
        @Expect(pluginSurfaceString(result, "approval"), "review")
    }

    @TestCase
    public func packageSummaryAggregatesNeedsReviewState() {
        let rows = JsonArray([])
        rows.add(gatewayPluginPackageProbeRowJson("dingtalk", true, false))
        let result = gatewayPluginsPackageStateSummaryJson(rows)
        @Expect(pluginSurfaceString(result, "packageProbe"), "needs-review")
    }
}
