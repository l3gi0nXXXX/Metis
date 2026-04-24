package metis.gateway.config

import magic.jsonable.*

import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

public func gatewayChannelBindingConstraintsJson(enabled: Bool, configured: Bool, hasModel: Bool): JsonArray {
    let constraints = JsonArray([])
    let requireEnabled = JsonObject()
    requireEnabled.put("name", JsonString("channel-enabled"))
    requireEnabled.put("satisfied", enabled.toJsonValue())
    requireEnabled.put("detail", JsonString(if (enabled) { "channel is enabled" } else { "channel must be enabled" }))
    constraints.add(requireEnabled)
    let requireConfigured = JsonObject()
    requireConfigured.put("name", JsonString("channel-configured"))
    requireConfigured.put("satisfied", configured.toJsonValue())
    requireConfigured.put("detail", JsonString(if (configured) { "channel credentials/config are present" } else { "channel needs configuration" }))
    constraints.add(requireConfigured)
    let requireModel = JsonObject()
    requireModel.put("name", JsonString("channel-model"))
    requireModel.put("satisfied", hasModel.toJsonValue())
    requireModel.put("detail", JsonString(if (hasModel) { "channel model binding exists" } else { "channel model binding is optional but recommended" }))
    constraints.add(requireModel)
    constraints
}

public func gatewayChannelBindingActionsJson(channelId: String, enabled: Bool, configured: Bool): JsonArray {
    let actions = JsonArray([])
    let inspect = JsonObject()
    inspect.put("action", JsonString("inspect-channel"))
    inspect.put("method", JsonString("channels.get"))
    let inspectParams = JsonObject()
    inspectParams.put("channelId", JsonString(channelId))
    inspect.put("params", inspectParams)
    actions.add(inspect)
    if (!enabled) {
        let enable = JsonObject()
        enable.put("action", JsonString("enable-master"))
        enable.put("method", JsonString("master_on"))
        enable.put("policyState", JsonString("disabled"))
        actions.add(enable)
    }
    if (!configured) {
        let configure = JsonObject()
        configure.put("action", JsonString("configure-channel"))
        configure.put("method", JsonString("channels.get"))
        configure.put("policyState", JsonString("pending-config"))
        configure.put("params", inspectParams)
        actions.add(configure)
    }
    let bindings = JsonObject()
    bindings.put("action", JsonString("inspect-bindings"))
    bindings.put("method", JsonString("channels.bindings"))
    bindings.put("params", inspectParams)
    actions.add(bindings)
    actions
}

public func gatewayPluginBindingConstraintsJson(installed: Bool, registered: Bool, enabled: Bool, configured: Bool, declaredChannelCount: Int64): JsonArray {
    let constraints = JsonArray([])
    let installedRow = JsonObject()
    installedRow.put("name", JsonString("plugin-installed"))
    installedRow.put("satisfied", installed.toJsonValue())
    installedRow.put("detail", JsonString(if (installed) { "plugin is installed" } else { "plugin must be installed" }))
    constraints.add(installedRow)
    let registeredRow = JsonObject()
    registeredRow.put("name", JsonString("plugin-registered"))
    registeredRow.put("satisfied", registered.toJsonValue())
    registeredRow.put("detail", JsonString(if (registered) { "plugin is registered" } else { "plugin must be registered" }))
    constraints.add(registeredRow)
    let enabledRow = JsonObject()
    enabledRow.put("name", JsonString("plugin-enabled"))
    enabledRow.put("satisfied", enabled.toJsonValue())
    enabledRow.put("detail", JsonString(if (enabled) { "plugin is enabled in gateway" } else { "plugin must be enabled in gateway config" }))
    constraints.add(enabledRow)
    let configuredRow = JsonObject()
    configuredRow.put("name", JsonString("plugin-configured"))
    configuredRow.put("satisfied", configured.toJsonValue())
    configuredRow.put("detail", JsonString(if (configured) { "plugin extra config is present" } else { "plugin needs config before binding" }))
    constraints.add(configuredRow)
    let declaredRow = JsonObject()
    declaredRow.put("name", JsonString("plugin-channel-declarations"))
    declaredRow.put("satisfied", (declaredChannelCount > 0).toJsonValue())
    declaredRow.put("detail", JsonString(if (declaredChannelCount > 0) { "plugin declares channel ids" } else { "plugin should declare channel ids" }))
    constraints.add(declaredRow)
    constraints
}

public func gatewayPluginBindingActionsJson(pluginId: String, installed: Bool, registered: Bool, enabled: Bool, configured: Bool): JsonArray {
    let actions = JsonArray([])
    let inspect = JsonObject()
    inspect.put("action", JsonString("inspect-plugin"))
    inspect.put("method", JsonString("plugins.get"))
    let inspectParams = JsonObject()
    inspectParams.put("pluginId", JsonString(pluginId))
    inspect.put("params", inspectParams)
    actions.add(inspect)
    if (!installed || !registered) {
        let discover = JsonObject()
        discover.put("action", JsonString("discover-plugin"))
        discover.put("method", JsonString("discover.detail"))
        discover.put("policyState", JsonString("missing"))
        actions.add(discover)
    }
    if (!enabled || !configured) {
        let configure = JsonObject()
        configure.put("action", JsonString("configure-plugin"))
        configure.put("method", JsonString("plugins.bindings"))
        configure.put("policyState", JsonString(if (!enabled) { "disabled" } else { "pending-config" }))
        configure.put("params", inspectParams)
        actions.add(configure)
    }
    let bindings = JsonObject()
    bindings.put("action", JsonString("inspect-bindings"))
    bindings.put("method", JsonString("plugins.bindings"))
    bindings.put("params", inspectParams)
    actions.add(bindings)
    actions
}
