package metis.gateway.runtime

import magic.jsonable.*

import metis.core.config.GatewayUserSettings

import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

public func gatewayBuildChannelHealthMonitor(
    user: GatewayUserSettings,
    healthState: String,
    constraints: JsonArray,
    actions: JsonArray
): JsonObject {
    let monitor = JsonObject()
    monitor.put("monitorEnabled", (user.channelHealthCheckMinutes > 0).toJsonValue())
    monitor.put("checkIntervalMinutes", user.channelHealthCheckMinutes.toJsonValue())
    monitor.put("staleThresholdMinutes", user.channelStaleEventThresholdMinutes.toJsonValue())
    monitor.put("maxRestartsPerHour", user.channelMaxRestartsPerHour.toJsonValue())
    monitor.put("healthState", JsonString(healthState))
    monitor.put("policyState", JsonString(if (healthState == "healthy" || healthState == "disabled") { "steady" } else { "attention" }))
    monitor.put("constraints", constraints)
    monitor.put("actions", actions)
    monitor.put("actionsNeeded", (actions.size() > 0).toJsonValue())
    monitor
}

public func gatewayBuildPluginHealthMonitor(
    user: GatewayUserSettings,
    healthState: String,
    constraints: JsonArray,
    actions: JsonArray
): JsonObject {
    let monitor = JsonObject()
    monitor.put("monitorEnabled", (user.channelHealthCheckMinutes > 0).toJsonValue())
    monitor.put("checkIntervalMinutes", user.channelHealthCheckMinutes.toJsonValue())
    monitor.put("staleThresholdMinutes", user.channelStaleEventThresholdMinutes.toJsonValue())
    monitor.put("maxRestartsPerHour", user.channelMaxRestartsPerHour.toJsonValue())
    monitor.put("healthState", JsonString(healthState))
    monitor.put("policyState", JsonString(if (healthState == "healthy" || healthState == "disabled") { "steady" } else { "attention" }))
    monitor.put("constraints", constraints)
    monitor.put("actions", actions)
    monitor.put("actionsNeeded", (actions.size() > 0).toJsonValue())
    monitor
}

public func gatewayBuildHealthItem(id: String, status: JsonObject, monitor: JsonObject): JsonObject {
    let item = JsonObject()
    item.put("id", JsonString(id))
    item.put("status", status)
    item.put("monitor", monitor)
    item
}

public func gatewayBuildChannelHealthActionRow(
    channelId: String,
    healthState: String,
    constraints: JsonArray,
    actions: JsonArray
): JsonObject {
    let actionRow = JsonObject()
    actionRow.put("channelId", JsonString(channelId))
    actionRow.put("healthState", JsonString(healthState))
    actionRow.put("constraints", constraints)
    actionRow.put("actions", actions)
    actionRow
}

public func gatewayBuildPluginHealthActionRow(
    pluginId: String,
    healthState: String,
    constraints: JsonArray,
    actions: JsonArray
): JsonObject {
    let actionRow = JsonObject()
    actionRow.put("pluginId", JsonString(pluginId))
    actionRow.put("healthState", JsonString(healthState))
    actionRow.put("constraints", constraints)
    actionRow.put("actions", actions)
    actionRow
}
