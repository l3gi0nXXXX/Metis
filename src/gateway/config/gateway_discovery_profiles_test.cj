package metis.gateway.config

import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

private func discoveryString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

@Test
public class GatewayDiscoveryProfilesTest {
    @TestCase
    public func batchApplySummaryUsesAppliedAndNoopStates() {
        let applied = gatewayBatchApplySummaryJson(JsonArray([JsonObject()]))
        let noop = gatewayBatchApplySummaryJson(JsonArray([]))
        @Expect(discoveryString(applied, "state"), "applied")
        @Expect(discoveryString(noop, "state"), "no-op")
    }

    @TestCase
    public func discoverDetailSummaryCarriesCatalogAndRows() {
        let channels = JsonArray([JsonString("qq")])
        let plugins = JsonArray([JsonString("dingtalk")])
        let result = gatewayDiscoverDetailSummaryJson(
            JsonArray([JsonString("qq")]),
            JsonArray([JsonString("dingtalk")]),
            JsonArray([JsonString("dingtalk")]),
            JsonArray([]),
            JsonArray([]),
            channels,
            plugins
        )
        @Expect(result.get("channels").getOrThrow().asArray().size(), 1)
        @Expect(result.get("plugins").getOrThrow().asArray().size(), 1)
    }
}
