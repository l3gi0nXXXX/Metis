package metis.gateway.config

import std.collection.ArrayList

import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

public func gatewayBootstrapCatalogPlanJson(): JsonObject {
    let channelIds = JsonArray([])
    for (entry in listGatewayChannelCatalogEntries()) {
        channelIds.add(JsonString(entry.id))
    }
    let pluginIds = JsonArray([])
    for (entry in listGatewayPluginCatalogEntries()) {
        if (!entry.builtin) {
            pluginIds.add(JsonString(entry.id))
        }
    }
    let out = JsonObject()
    out.put("channelIds", channelIds)
    out.put("pluginIds", pluginIds)
    out
}

public func gatewayBootstrapChannelIds(): Array<String> {
    let ids = ArrayList<String>()
    for (entry in listGatewayChannelCatalogEntries()) {
        ids.add(entry.id)
    }
    ids.toArray()
}

public func gatewayBootstrapPluginIds(): Array<String> {
    let ids = ArrayList<String>()
    for (entry in listGatewayPluginCatalogEntries()) {
        if (!entry.builtin) {
            ids.add(entry.id)
        }
    }
    ids.toArray()
}
