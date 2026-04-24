package metis.gateway.config

import magic.jsonable.*

import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

public func gatewaySynthesizedRuntimeAccounts(configuredAccountIds: JsonArray, defaultAccountId: String): JsonArray {
    let synthesized = JsonArray([])
    for (i in 0..configuredAccountIds.size()) {
        let accountId = try { configuredAccountIds[i].asString().getValue().trimAscii() } catch (_e: Exception) { defaultAccountId }
        let row = JsonObject()
        row.put("accountId", JsonString(if (accountId.isEmpty()) { defaultAccountId } else { accountId }))
        synthesized.add(row)
    }
    synthesized
}

public func gatewayProbeResultJson(ok: Bool, status: String, timeoutMs: Int64): JsonObject {
    let probeResult = JsonObject()
    probeResult.put("ok", ok.toJsonValue())
    probeResult.put("status", JsonString(status))
    probeResult.put("timeoutMs", timeoutMs.toJsonValue())
    probeResult
}

public func gatewayProbeTimestampMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toMilliseconds()
}
