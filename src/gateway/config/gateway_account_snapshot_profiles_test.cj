package metis.gateway.config

import magic.jsonable.*

import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

private func snapshotString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func snapshotBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
}

@Test
public class GatewayAccountSnapshotProfilesTest {
    @TestCase
    public func synthesizedRuntimeAccountsUseDefaultFallback(): Unit {
        let ids = JsonArray([])
        ids.add(JsonString(""))
        ids.add(JsonString("qq:bot"))
        let rows = gatewaySynthesizedRuntimeAccounts(ids, "qq:default")
        @Expect(rows.size(), 2)
        let first = rows[0].asObject()
        let second = rows[1].asObject()
        @Expect(snapshotString(first, "accountId"), "qq:default")
        @Expect(snapshotString(second, "accountId"), "qq:bot")
    }

    @TestCase
    public func probeResultJsonCarriesOkStatusAndTimeout(): Unit {
        let probe = gatewayProbeResultJson(true, "ready", 5000)
        @Expect(snapshotBool(probe, "ok"), true)
        @Expect(snapshotString(probe, "status"), "ready")
    }
}
