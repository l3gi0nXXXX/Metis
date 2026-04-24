package metis.gateway.config

import metis.core.config.GatewayUserSettings

import stdx.encoding.json.JsonObject

public func gatewayChannelMetaJson(user: GatewayUserSettings): JsonObject {
    let obj = JsonObject()
    for (entry in listGatewayChannelCatalogEntries()) {
        let row = entry.toJson()
        row.put("supports", gatewayChannelSupportsJson(user, entry.id))
        obj.put(entry.id, row)
    }
    obj
}

public func gatewayPluginMetaJson(user: GatewayUserSettings): JsonObject {
    let obj = JsonObject()
    for (entry in listGatewayPluginCatalogEntries()) {
        if (!entry.builtin) {
            let row = entry.toJson()
            row.put("supports", gatewayPluginSupportsJson(user, entry.id))
            obj.put(entry.id, row)
        }
    }
    obj
}
