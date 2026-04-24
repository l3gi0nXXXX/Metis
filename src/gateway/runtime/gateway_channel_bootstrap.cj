package metis.gateway.runtime

import magic.jsonable.*

import metis.core.config.GatewayUserSettings
import metis.gateway.config.{gatewayBootstrapChannelIds, gatewayBootstrapPluginIds, gatewayConfiguredPrimedBindings}
import metis.gateway.core.gatewayChannelRuntimeMarkBootstrap

import stdx.encoding.json.JsonObject

public func gatewayPrimeConfiguredChannelBindings(user: GatewayUserSettings): JsonObject {
    let configuredBindings = gatewayConfiguredChannelBindingsRegistry(user)
    let primedBindings = gatewayConfiguredPrimedBindings(configuredBindings)
    let (configuredBindingCount, primedBindingCount) = gatewayPrimeConfiguredChannelBindingAccounts(user)
    let bootstrap = gatewayChannelRuntimeMarkBootstrap(
        gatewayBootstrapChannelIds(),
        gatewayBootstrapPluginIds(),
        configuredBindings: configuredBindings,
        primedBindings: primedBindings,
        configuredBindingCount: configuredBindingCount,
        primedBindingCount: primedBindingCount
    )
    let result = JsonObject()
    result.put("bootstrap", bootstrap)
    result.put("configuredBindings", configuredBindings)
    result.put("primedBindings", primedBindings)
    result.put("configuredBindingCount", configuredBindingCount.toJsonValue())
    result.put("primedBindingCount", primedBindingCount.toJsonValue())
    result
}
