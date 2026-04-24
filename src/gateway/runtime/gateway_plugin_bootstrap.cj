package metis.gateway.runtime

import metis.gateway.config.ensureInstalledGatewayPluginsRegistered

/**
 * 在装配网关前调用：自动发现并登记已安装插件。
 * 约定目录：`~/.metis/gateway-plugins/xx/` 下的兼容 manifest。
 */
public func ensureGatewayChannelPluginsRegistered(): Unit {
    ensureInstalledGatewayPluginsRegistered()
}
