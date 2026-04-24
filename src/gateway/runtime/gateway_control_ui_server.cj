package metis.gateway.runtime

import metis.core.config.CliSettingManager
import metis.gateway.config.buildGatewayConfigFromUserSettings
import metis.gateway.model.GatewayConfig

// Historical compatibility shim only.
// Control UI now lives exclusively on the shared GatewayHttpSurface.
public class DashboardServer {
    public static func url(): String {
        let cfg = buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())
        GatewayControlUiRuntime.controlUiBinding(cfg).httpUrl
    }

    public static func isRunning(): Bool {
        GatewayHttpSurface.isRunning()
    }

    public static func stopIfRunning(): Bool {
        let running = GatewayHttpSurface.isRunning()
        if (running) {
            GatewayHttpSurface.stopIfRunning()
        }
        running
    }

    public static func reload(cfg!: GatewayConfig = buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())): Bool {
        GatewayHttpSurface.stopIfRunning()
        GatewayHttpSurface.startIfNeeded(cfg)
        GatewayHttpSurface.isRunning()
    }

    public static func startIfNeeded(cfg!: GatewayConfig = buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())): Unit {
        GatewayHttpSurface.startIfNeeded(cfg)
    }
}
