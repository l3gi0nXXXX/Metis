package metis.gateway.tools

import metis.core.config.CliSettingManager

/** 兼容语义：deny 优先；allow 非空时为白名单。 */
public func isGatewayToolAllowed(toolName: String): Bool {
    let t = CliSettingManager.setting.gateway.tools
    for (d in t.deny) {
        let x = d.trimAscii()
        if (x == "*" || x == toolName) {
            return false
        }
    }
    if (t.allow.isEmpty()) {
        return true
    }
    for (a in t.allow) {
        let x = a.trimAscii()
        if (x == "*" || x == toolName) {
            return true
        }
    }
    false
}
