package metis.gateway.config

import metis.core.config.GatewayUserSettings
import magic.jsonable.*

import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

private func gatewayBindingBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_: Exception) { false }
        case None => false
    }
}

private func gatewayBindingStringParam(obj: JsonObject, keys: Array<String>, defaultValue: String): String {
    for (key in keys) {
        match (obj.get(key)) {
            case Some(v) =>
                try {
                    let value = v.asString().getValue().trimAscii()
                    if (!value.isEmpty()) {
                        return value
                    }
                } catch (_: Exception) {
                    ()
                }
            case None => ()
        }
    }
    defaultValue
}

private func gatewayHostArray(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asArray() } catch (_: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

public func gatewayPluginApprovalRowJson(
    pluginId: String,
    installed: Bool,
    registered: Bool,
    enabled: Bool,
    configured: Bool
): JsonObject {
    let row = JsonObject()
    let policyState = if (installed && registered && enabled && configured) {
        "routable"
    } else if (installed && registered && configured) {
        "configured"
    } else if (installed && registered) {
        "available"
    } else {
        "missing"
    }
    let approvalState = if (installed && registered && configured) {
        "approved"
    } else if (installed || registered) {
        "review"
    } else {
        "missing"
    }
    row.put("pluginId", JsonString(pluginId))
    row.put("approvalState", JsonString(approvalState))
    row.put("policyState", JsonString(policyState))
    row.put("actionsNeeded", (!(installed && registered && configured)).toJsonValue())
    let constraints = JsonArray([])
    let registryConstraint = JsonObject()
    registryConstraint.put("name", JsonString("plugin-registered"))
    registryConstraint.put("ok", registered.toJsonValue())
    registryConstraint.put("detail", JsonString(if (registered) { "plugin is registered" } else { "plugin must be registered" }))
    constraints.add(registryConstraint)
    let configConstraint = JsonObject()
    configConstraint.put("name", JsonString("plugin-configured"))
    configConstraint.put("ok", configured.toJsonValue())
    configConstraint.put("detail", JsonString(if (configured) { "plugin config is present" } else { "plugin config missing" }))
    constraints.add(configConstraint)
    row.put("constraints", constraints)
    let actions = JsonArray([])
    let inspect = JsonObject()
    inspect.put("action", JsonString("inspect-plugin"))
    inspect.put("method", JsonString("plugins.get"))
    let inspectParams = JsonObject()
    inspectParams.put("pluginId", JsonString(pluginId))
    inspect.put("params", inspectParams)
    actions.add(inspect)
    if (!(installed && registered && configured)) {
        let setup = JsonObject()
        setup.put("action", JsonString("review-setup"))
        setup.put("method", JsonString("plugins.setup"))
        setup.put("params", inspectParams)
        actions.add(setup)
    }
    row.put("actions", actions)
    row
}

public func gatewayPluginPackageProbeRowJson(pluginId: String, installed: Bool, registered: Bool): JsonObject {
    let row = JsonObject()
    row.put("pluginId", JsonString(pluginId))
    row.put("installed", installed.toJsonValue())
    row.put("registered", registered.toJsonValue())
    row.put("probeState", JsonString(if (installed && registered) { "ready" } else if (installed) { "unregistered" } else { "missing" }))
    row.put("actionsNeeded", (!(installed && registered)).toJsonValue())
    let constraints = JsonArray([])
    let installedConstraint = JsonObject()
    installedConstraint.put("name", JsonString("plugin-installed"))
    installedConstraint.put("ok", installed.toJsonValue())
    installedConstraint.put("detail", JsonString(if (installed) { "plugin package is installed" } else { "plugin package missing" }))
    constraints.add(installedConstraint)
    let registeredConstraint = JsonObject()
    registeredConstraint.put("name", JsonString("plugin-registered"))
    registeredConstraint.put("ok", registered.toJsonValue())
    registeredConstraint.put("detail", JsonString(if (registered) { "plugin package is registered" } else { "plugin package not registered" }))
    constraints.add(registeredConstraint)
    row.put("constraints", constraints)
    let actions = JsonArray([])
    let discover = JsonObject()
    discover.put("action", JsonString("discover-plugin"))
    discover.put("method", JsonString("discover.detail"))
    actions.add(discover)
    row.put("actions", actions)
    row
}

public func gatewayPluginSetupRowJson(pluginId: String, setupSupported: Bool, configured: Bool, docsUrl: JsonObject): JsonObject {
    let row = JsonObject()
    row.put("pluginId", JsonString(pluginId))
    row.put("setupSupported", setupSupported.toJsonValue())
    row.put("configured", configured.toJsonValue())
    row.put("state", JsonString(if (configured) { "configured" } else if (setupSupported) { "needs-setup" } else { "manual-config" }))
    row.put("docsUrl", docsUrl.get("docsUrl") ?? JsonString(""))
    row.put("actionsNeeded", (!configured).toJsonValue())
    let actions = JsonArray([])
    let inspect = JsonObject()
    inspect.put("action", JsonString("inspect-plugin"))
    inspect.put("method", JsonString("plugins.get"))
    let inspectParams = JsonObject()
    inspectParams.put("pluginId", JsonString(pluginId))
    inspect.put("params", inspectParams)
    actions.add(inspect)
    if (!configured) {
        let bindings = JsonObject()
        bindings.put("action", JsonString("review-bindings"))
        bindings.put("method", JsonString("plugins.bindings"))
        bindings.put("params", inspectParams)
        actions.add(bindings)
    }
    row.put("actions", actions)
    row
}

public func gatewayPluginsApprovalSummaryJson(rows: JsonArray): JsonObject {
    let result = JsonObject()
    let actions = JsonArray([])
    var actionsNeeded: Int64 = 0
    var approvedCount: Int64 = 0
    for (i in 0..rows.size()) {
        let row = try { rows[i].asObject() } catch (_: Exception) { JsonObject() }
        if (gatewayBindingBool(row, "actionsNeeded")) {
            actionsNeeded += 1
        }
        if (gatewayBindingStringParam(row, ["approvalState"], "") == "approved") {
            approvedCount += 1
        }
        let rowActions = gatewayHostArray(row, "actions")
        for (j in 0..rowActions.size()) {
            actions.add(rowActions[j])
        }
    }
    let rowCount = Int64(rows.size())
    result.put("items", rows)
    result.put("approval", JsonString(if (rowCount == 0) { "steady" } else if (actionsNeeded == 0 && approvedCount == rowCount) { "approved" } else { "review" }))
    result.put("count", rowCount.toJsonValue())
    result.put("actionsNeeded", actionsNeeded.toJsonValue())
    result.put("actions", actions)
    result
}

public func gatewayPluginsPackageStateSummaryJson(rows: JsonArray): JsonObject {
    let result = JsonObject()
    let actions = JsonArray([])
    var actionsNeeded: Int64 = 0
    var readyCount: Int64 = 0
    for (i in 0..rows.size()) {
        let row = try { rows[i].asObject() } catch (_: Exception) { JsonObject() }
        if (gatewayBindingBool(row, "actionsNeeded")) {
            actionsNeeded += 1
        }
        if (gatewayBindingStringParam(row, ["probeState", "packageProbe"], "") == "ready") {
            readyCount += 1
        }
        let rowActions = gatewayHostArray(row, "actions")
        for (j in 0..rowActions.size()) {
            actions.add(rowActions[j])
        }
    }
    let rowCount = Int64(rows.size())
    result.put("items", rows)
    result.put("packageProbe", JsonString(if (rowCount == 0) { "steady" } else if (actionsNeeded == 0 && readyCount == rowCount) { "ready" } else { "needs-review" }))
    result.put("count", rowCount.toJsonValue())
    result.put("actionsNeeded", actionsNeeded.toJsonValue())
    result.put("actions", actions)
    result
}

public func gatewayPluginsSetupSummaryJson(rows: JsonArray): JsonObject {
    let result = JsonObject()
    let actions = JsonArray([])
    var actionsNeeded: Int64 = 0
    var configuredCount: Int64 = 0
    for (i in 0..rows.size()) {
        let row = try { rows[i].asObject() } catch (_: Exception) { JsonObject() }
        if (gatewayBindingBool(row, "actionsNeeded")) {
            actionsNeeded += 1
        }
        if (gatewayBindingStringParam(row, ["state"], "") == "configured") {
            configuredCount += 1
        }
        let rowActions = gatewayHostArray(row, "actions")
        for (j in 0..rowActions.size()) {
            actions.add(rowActions[j])
        }
    }
    let rowCount = Int64(rows.size())
    result.put("items", rows)
    result.put("setup", JsonString(if (rowCount == 0) { "steady" } else if (actionsNeeded == 0 && configuredCount == rowCount) { "configured" } else { "available" }))
    result.put("count", rowCount.toJsonValue())
    result.put("actionsNeeded", actionsNeeded.toJsonValue())
    result.put("actions", actions)
    result
}
