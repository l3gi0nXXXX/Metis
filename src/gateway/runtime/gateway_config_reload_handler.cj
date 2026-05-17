package metis.gateway.runtime

import metis.core.config.GatewayUserSettings
import metis.gateway.config.{GatewayPreparedAdapterRegistration, gatewayPreparedBuiltinAdapterRegistrations}
import metis.gateway.core.GatewayService

import magic.log.LogUtils

import std.collection.ArrayList

public interface GatewayReloadChannelRuntime {
    func reconcileChannel(channelId: String, registrations: Array<GatewayPreparedAdapterRegistration>): Unit
}

public class GatewayServiceReloadChannelRuntime <: GatewayReloadChannelRuntime {
    private let gateway: GatewayService

    public init(gateway: GatewayService) {
        this.gateway = gateway
    }

    public func reconcileChannel(channelId: String, registrations: Array<GatewayPreparedAdapterRegistration>): Unit {
        let normalized = channelId.trimAscii().toAsciiLower()
        if (normalized.isEmpty()) {
            return
        }
        this.gateway.stopChannel(normalized, reason: "config-reload", manualStop: false)
        this.gateway.clearChannelRegistrations(normalized)
        for (prepared in registrations) {
            if (prepared.profile.channelId != normalized) {
                continue
            }
            this.gateway.registerAdapter(
                prepared.adapter,
                channelId: prepared.profile.channelId,
                accountId: prepared.profile.accountId,
                pluginId: prepared.profile.pluginId,
                origin: prepared.profile.origin,
                runtimeKind: prepared.profile.runtimeKind,
                compatibilityMode: prepared.profile.compatibilityMode,
                label: prepared.profile.label,
                detailLabel: prepared.profile.detailLabel,
                enabled: prepared.profile.enabled,
                configured: prepared.profile.configured,
                healthMonitorEnabled: prepared.profile.healthMonitorEnabled
            )
        }
        this.gateway.startChannel(normalized)
    }
}

private func gatewayReloadFilterRegistrations(
    registrations: Array<GatewayPreparedAdapterRegistration>,
    channelId: String
): Array<GatewayPreparedAdapterRegistration> {
    let out = ArrayList<GatewayPreparedAdapterRegistration>()
    let normalized = channelId.trimAscii().toAsciiLower()
    for (prepared in registrations) {
        if (prepared.profile.channelId == normalized) {
            out.add(prepared)
        }
    }
    out.toArray()
}

public func applyGatewayHotReload(
    plan: GatewayReloadPlan,
    nextUser: GatewayUserSettings,
    runtime: GatewayReloadChannelRuntime
): Unit {
    if (plan.restartChannels.size == 0) {
        if (plan.hotReasons.size > 0) {
            LogUtils.info("Gateway.config.reload: hot config change applied without channel restart")
        }
        return
    }
    let prepared = gatewayPreparedBuiltinAdapterRegistrations(nextUser, nextUser.channelHealthCheckMinutes > 0)
    for (channelId in plan.restartChannels) {
        let channelRegistrations = gatewayReloadFilterRegistrations(prepared, channelId)
        LogUtils.info("Gateway.config.reload: reconciling channel=${channelId} registrations=${channelRegistrations.size}")
        runtime.reconcileChannel(channelId, channelRegistrations)
    }
    if (plan.hotReasons.size > 0) {
        LogUtils.info("Gateway.config.reload: hot reload applied")
    }
}

public class GatewayServiceConfigReloadCallbacks <: GatewayConfigReloadCallbacks {
    private let runtime: GatewayReloadChannelRuntime

    public init(runtime: GatewayReloadChannelRuntime) {
        this.runtime = runtime
    }

    public func onHotReload(plan: GatewayReloadPlan, nextUser: GatewayUserSettings): Unit {
        applyGatewayHotReload(plan, nextUser, this.runtime)
    }

    public func onRestartRequired(plan: GatewayReloadPlan, _nextUser: GatewayUserSettings): Unit {
        let reason = if (plan.restartReasons.size > 0) {
            String.join(plan.restartReasons.toArray(), delimiter: ", ")
        } else {
            String.join(plan.changedPaths, delimiter: ", ")
        }
        LogUtils.error("Gateway.config.reload: gateway restart required (${reason})")
    }
}
