package metis.gateway.config

import std.collection.ArrayList

/**
 * 内置已实现的渠道 id（与 `ChannelAdapter.name`、`channelToString` 一致）。
 *
 * **内置渠道（飞书/QQ）**：继续在 `gateway_config_factory` 中直接装配。
 *
 * **扩展渠道（兼容插件模式）**：
 * 1. 在模型层使用 `ChannelType.Extension("<id>")` 与 `InboundMessage`；
 * 2. 安装插件目录到 `~/.metis/gateway-plugins/<plugin-id>`，并提供兼容 manifest；
 * 3. 用户在 `metis.json` 的 `gateway.gatewayPlugins` 中启用，并在 `gateway.channelsExtra.<pluginId>` 下放配置。
 */
public const GATEWAY_CHANNEL_FEISHU: String = "feishu"
public const GATEWAY_CHANNEL_QQ: String = "qq"
public const GATEWAY_CHANNEL_TELEGRAM: String = "telegram"
public const GATEWAY_CHANNEL_SLACK: String = "slack"
public const GATEWAY_CHANNEL_DISCORD: String = "discord"

/** 当前版本已接线的内置渠道列表（用于 `gateway channel list`）。 */
public func builtinGatewayChannelIds(): Array<String> {
    let out = ArrayList<String>()
    for (entry in listGatewayChannelCatalogEntries()) {
        if (entry.builtin && !out.contains(entry.id)) {
            out.add(entry.id)
        }
    }
    if (out.isEmpty()) {
        return [GATEWAY_CHANNEL_FEISHU, GATEWAY_CHANNEL_QQ]
    }
    out.toArray()
}

/** 已通过 `GatewayChannelPluginRegistry` 登记的扩展插件 id（用于展示）。 */
public func registeredGatewayPluginIds(): Array<String> {
    GatewayChannelPluginRegistry.allPluginIds()
}
