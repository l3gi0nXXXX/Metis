package metis.gateway.runtime

import magic.jsonable.*

import metis.core.config.GatewayUserSettings
import metis.gateway.config.{listGatewayChannelCatalogEntries, listGatewayPluginCatalogEntries}

import std.convert.Parsable
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

public func gatewayBuildChannelsHealthJson(
    user: GatewayUserSettings,
    statusResolver: (String, Bool, Int64) -> JsonObject
): JsonObject {
    let result = JsonObject()
    let items = JsonArray([])
    let actions = JsonArray([])
    let byHealthState = JsonObject()
    var enabledCount: Int64 = 0
    var healthyCount: Int64 = 0
    var degradedCount: Int64 = 0
    var actionsNeeded: Int64 = 0
    let timeoutMs = user.channelHealthCheckMinutes * 60 * 1000
    for (entry in listGatewayChannelCatalogEntries()) {
        let status = statusResolver(entry.id, true, timeoutMs)
        let policy = gatewayChannelHealthPolicy(user, entry.id, status)
        let enabled = match (policy.get("enabled")) { case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { false } case None => false }
        let healthState = match (policy.get("healthState")) { case Some(v) => try { v.asString().getValue() } catch (_e: Exception) { "unknown" } case None => "unknown" }
        let constraints = match (policy.get("constraints")) { case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) } case None => JsonArray([]) }
        let actionList = match (policy.get("actions")) { case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) } case None => JsonArray([]) }
        if (enabled) {
            enabledCount += 1
        }
        if (healthState == "healthy") {
            healthyCount += 1
        } else if (healthState != "disabled") {
            degradedCount += 1
        }
        let current = match (byHealthState.get(healthState)) {
            case Some(v) => try { Int64.parse(v.toJsonString()) } catch (_e: Exception) { 0 }
            case None => 0
        }
        byHealthState.put(healthState, (current + 1).toJsonValue())
        let monitor = gatewayBuildChannelHealthMonitor(user, healthState, constraints, actionList)
        items.add(gatewayBuildHealthItem(entry.id, status, monitor))
        if (actionList.size() > 0) {
            actionsNeeded += 1
            actions.add(gatewayBuildChannelHealthActionRow(entry.id, healthState, constraints, actionList))
        }
    }
    result.put("items", items)
    result.put("actions", actions)
    result.put("enabledCount", enabledCount.toJsonValue())
    result.put("healthyCount", healthyCount.toJsonValue())
    result.put("degradedCount", degradedCount.toJsonValue())
    result.put("actionsNeeded", actionsNeeded.toJsonValue())
    result.put("byHealthState", byHealthState)
    result.put("policyState", JsonString(if (degradedCount > 0) { "attention" } else { "steady" }))
    result.put("healthy", (degradedCount == 0 && gatewayHasAnyEnabledChannel(user)).toJsonValue())
    result
}

public func gatewayBuildPluginsHealthJson(
    user: GatewayUserSettings,
    statusResolver: (String, Bool, Int64) -> JsonObject
): JsonObject {
    let result = JsonObject()
    let items = JsonArray([])
    let actions = JsonArray([])
    let byHealthState = JsonObject()
    var enabledCount: Int64 = 0
    var healthyCount: Int64 = 0
    var degradedCount: Int64 = 0
    var actionsNeeded: Int64 = 0
    let timeoutMs = user.channelHealthCheckMinutes * 60 * 1000
    for (entry in listGatewayPluginCatalogEntries()) {
        if (entry.builtin) {
            continue
        }
        let status = statusResolver(entry.id, true, timeoutMs)
        let policy = gatewayPluginHealthPolicy(user, entry.id, status)
        let enabled = match (policy.get("enabled")) { case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { false } case None => false }
        let healthState = match (policy.get("healthState")) { case Some(v) => try { v.asString().getValue() } catch (_e: Exception) { "unknown" } case None => "unknown" }
        let constraints = match (policy.get("constraints")) { case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) } case None => JsonArray([]) }
        let actionList = match (policy.get("actions")) { case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) } case None => JsonArray([]) }
        if (enabled) {
            enabledCount += 1
        }
        if (healthState == "healthy") {
            healthyCount += 1
        } else if (healthState != "disabled") {
            degradedCount += 1
        }
        let current = match (byHealthState.get(healthState)) {
            case Some(v) => try { Int64.parse(v.toJsonString()) } catch (_e: Exception) { 0 }
            case None => 0
        }
        byHealthState.put(healthState, (current + 1).toJsonValue())
        let monitor = gatewayBuildPluginHealthMonitor(user, healthState, constraints, actionList)
        items.add(gatewayBuildHealthItem(entry.id, status, monitor))
        if (actionList.size() > 0) {
            actionsNeeded += 1
            actions.add(gatewayBuildPluginHealthActionRow(entry.id, healthState, constraints, actionList))
        }
    }
    result.put("items", items)
    result.put("actions", actions)
    result.put("enabledCount", enabledCount.toJsonValue())
    result.put("healthyCount", healthyCount.toJsonValue())
    result.put("degradedCount", degradedCount.toJsonValue())
    result.put("actionsNeeded", actionsNeeded.toJsonValue())
    result.put("byHealthState", byHealthState)
    result.put("policyState", JsonString(if (degradedCount > 0) { "attention" } else { "steady" }))
    result.put("healthy", (degradedCount == 0 && (enabledCount > 0 || items.size() == 0)).toJsonValue())
    result
}
