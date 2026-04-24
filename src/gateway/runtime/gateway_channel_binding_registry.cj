package metis.gateway.runtime

import magic.jsonable.*

import metis.core.config.GatewayUserSettings
import metis.gateway.config.gatewayBindingRegistryRowJson
import metis.gateway.core.{gatewayChannelRuntimeAccountsJson, gatewayPluginRuntimeAccountsJson}

import stdx.encoding.json.JsonObject

public func gatewayChannelBindingRegistryRow(user: GatewayUserSettings, channelId: String): JsonObject {
    let configured = gatewayConfiguredChannelBindingRow(user, channelId)
    let runtimeAccounts = gatewayChannelRuntimeAccountsJson(channelId)
    gatewayBindingRegistryRowJson("channelId", channelId, configured, runtimeAccounts)
}

public func gatewayPluginBindingRegistryRow(user: GatewayUserSettings, pluginId: String): JsonObject {
    let configured = gatewayConfiguredPluginBindingRow(user, pluginId)
    let runtimeAccounts = gatewayPluginRuntimeAccountsJson(pluginId)
    gatewayBindingRegistryRowJson("pluginId", pluginId, configured, runtimeAccounts)
}
