package metis.gateway.config

import magic.jsonable.*

import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

public func gatewayDiscoverDetailSummaryJson(
    builtinChannelIds: JsonValue,
    registeredPluginIds: JsonValue,
    installedPluginIds: JsonValue,
    channelCatalog: JsonValue,
    pluginCatalog: JsonValue,
    channels: JsonArray,
    plugins: JsonArray
): JsonObject {
    let result = JsonObject()
    result.put("builtinChannels", builtinChannelIds)
    result.put("registeredPluginIds", registeredPluginIds)
    result.put("installedPluginIds", installedPluginIds)
    result.put("channelCatalog", channelCatalog)
    result.put("pluginCatalog", pluginCatalog)
    result.put("channels", channels)
    result.put("plugins", plugins)
    result
}

public func gatewayBatchApplySummaryJson(items: JsonArray, stateWhenApplied!: String = "applied"): JsonObject {
    let result = JsonObject()
    result.put("items", items)
    result.put("applied", (items.size() > 0).toJsonValue())
    result.put("count", items.size().toJsonValue())
    result.put("state", JsonString(if (items.size() > 0) { stateWhenApplied } else { "no-op" }))
    result
}
