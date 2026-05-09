package metis.gateway.runtime

import metis.core.config.GatewayUserSettings
import metis.gateway.core.setGatewayOpenClawCompatHostLifecycleHooks
import metis.gateway.openclaw_channel.registerOpenClawCapturedChannelPlugins
import metis.gateway.openclaw_channel_http.OpenClawBridgeRunner
import metis.gateway.openclaw_http.registerOpenClawCapturedHttpRoutes
import metis.gateway.openclaw_runtime.{OpenClawCompatHostManager, OpenClawCompatHostProcessRunner, OpenClawCompatRegistrySyncSummary, openClawCompatHostConfigFromGatewaySettings}

import stdx.encoding.json.{JsonObject, JsonString}

private var gatewayOpenClawCompatHostManager: Option<OpenClawCompatHostManager> = None<OpenClawCompatHostManager>

private class GatewayOpenClawCompatHostBridgeRunner <: OpenClawBridgeRunner {
    private let manager: OpenClawCompatHostManager

    public init(manager: OpenClawCompatHostManager) {
        this.manager = manager
    }

    public func invoke(method: String, payload: JsonObject): JsonObject {
        this.manager.invoke(method, payload)
    }
}

private func gatewayOpenClawCompatHostDisabledSnapshot(user: GatewayUserSettings): JsonObject {
    let manager = OpenClawCompatHostManager(openClawCompatHostConfigFromGatewaySettings(user))
    let config = openClawCompatHostConfigFromGatewaySettings(user)
    if (!config.enabled) {
        let _ = manager.start()
    }
    manager.snapshotJson()
}

private func gatewayOpenClawCompatHostSyncGatewayRegistries(manager: OpenClawCompatHostManager): Unit {
    let bridge = manager.gatewayRegistryBridge()
    let runner = GatewayOpenClawCompatHostBridgeRunner(manager)
    manager.setRegistrySyncSummary(
        OpenClawCompatRegistrySyncSummary(
            channels: registerOpenClawCapturedChannelPlugins(bridge.raw, runner),
            httpRoutes: registerOpenClawCapturedHttpRoutes(bridge.raw, runner),
            tools: bridge.toolCount(),
            providers: bridge.providerCount(),
            hooks: bridge.hookCount()
        )
    )
}

public func gatewayInstallOpenClawCompatHostLifecycleHooks(): Unit {
    setGatewayOpenClawCompatHostLifecycleHooks(
        Some({ user: GatewayUserSettings => gatewayOpenClawCompatHostStart(user) }),
        Some({ user: GatewayUserSettings => gatewayOpenClawCompatHostStop(user) })
    )
}

public func gatewayOpenClawCompatHostStart(user: GatewayUserSettings): JsonObject {
    let manager = OpenClawCompatHostManager(openClawCompatHostConfigFromGatewaySettings(user))
    gatewayOpenClawCompatHostManager = Some(manager)
    let status = manager.start()
    if (status.ok && status.state == "running") {
        gatewayOpenClawCompatHostSyncGatewayRegistries(manager)
    }
    manager.snapshotJson()
}

public func gatewayOpenClawCompatHostStartWithRunnerForTest(user: GatewayUserSettings, runner: OpenClawCompatHostProcessRunner): JsonObject {
    let manager = OpenClawCompatHostManager(openClawCompatHostConfigFromGatewaySettings(user), runner: runner)
    gatewayOpenClawCompatHostManager = Some(manager)
    let status = manager.start()
    if (status.ok && status.state == "running") {
        gatewayOpenClawCompatHostSyncGatewayRegistries(manager)
    }
    manager.snapshotJson()
}

public func gatewayOpenClawCompatHostStop(user: GatewayUserSettings): JsonObject {
    match (gatewayOpenClawCompatHostManager) {
        case Some(manager) =>
            let _ = manager.stop()
            let snapshot = manager.snapshotJson()
            gatewayOpenClawCompatHostManager = None<OpenClawCompatHostManager>
            return snapshot
        case None =>
            let manager = OpenClawCompatHostManager(openClawCompatHostConfigFromGatewaySettings(user))
            let _ = manager.stop()
            manager.snapshotJson()
    }
}

public func gatewayOpenClawCompatHostHealth(user: GatewayUserSettings): JsonObject {
    match (gatewayOpenClawCompatHostManager) {
        case Some(manager) =>
            let _ = manager.health()
            return manager.snapshotJson()
        case None =>
            gatewayOpenClawCompatHostDisabledSnapshot(user)
    }
}

public func gatewayOpenClawCompatHostSnapshot(user: GatewayUserSettings): JsonObject {
    match (gatewayOpenClawCompatHostManager) {
        case Some(manager) => manager.snapshotJson()
        case None => gatewayOpenClawCompatHostDisabledSnapshot(user)
    }
}
