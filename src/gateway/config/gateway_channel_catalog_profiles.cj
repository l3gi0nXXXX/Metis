package metis.gateway.config

import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

public func gatewayChannelOrderJson(): JsonArray {
    let arr = JsonArray([])
    for (entry in listGatewayChannelCatalogEntries()) {
        arr.add(JsonString(entry.id))
    }
    arr
}

public func gatewayPluginOrderJson(): JsonArray {
    let arr = JsonArray([])
    for (entry in listGatewayPluginCatalogEntries()) {
        if (!entry.builtin) {
            arr.add(JsonString(entry.id))
        }
    }
    arr
}

public func gatewayChannelLabelsJson(): JsonObject {
    let obj = JsonObject()
    for (entry in listGatewayChannelCatalogEntries()) {
        obj.put(entry.id, JsonString(entry.label))
    }
    obj
}

public func gatewayChannelDetailLabelsJson(): JsonObject {
    let obj = JsonObject()
    for (entry in listGatewayChannelCatalogEntries()) {
        obj.put(entry.id, JsonString(entry.detailLabel))
    }
    obj
}

public func gatewayChannelSystemImagesJson(): JsonObject {
    let obj = JsonObject()
    for (entry in listGatewayChannelCatalogEntries()) {
        obj.put(entry.id, JsonString(entry.systemImage))
    }
    obj
}
