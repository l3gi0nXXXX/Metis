package metis.gateway.runtime

import metis.core.config.CliSettingManager
import metis.gateway.channels.feishu.FeishuAdapter
import metis.gateway.core.*

/**
 * P0 启动入口（样例）。
 *
 * 从 `~/.metis/metis.json` 的 `gateway` 段读取用户配置。
 * 可用 `magic-cli gateway ...` 子命令修改持久化配置。
 */
public func buildP0Gateway(): (GatewayService, FeishuAdapter) {
    buildGatewayServiceFromUserSettings(CliSettingManager.readGatewaySettings())
}
