package metis.gateway.config

import metis.core.config.GatewayUserSettings
import metis.gateway.channels.feishu.{gatewayFeishuListAccountIds, gatewayFeishuResolveAccount}
import metis.gateway.channels.qq.{gatewayQqListAccountIds, gatewayQqResolveAccount}
import metis.gateway.channels.telegram.{gatewayTelegramListAccountIds, gatewayTelegramResolveAccount}

import std.collection.ArrayList

public class GatewayAdapterRegistrationProfile {
    public let channelId: String
    public let accountId: String
    public let pluginId: String
    public let origin: String
    public let runtimeKind: String
    public let compatibilityMode: String
    public let label: String
    public let detailLabel: String
    public let enabled: Bool
    public let configured: Bool
    public let healthMonitorEnabled: Bool

    public init(
        channelId: String,
        accountId: String,
        pluginId: String,
        origin: String,
        runtimeKind: String,
        compatibilityMode: String,
        label: String,
        detailLabel: String,
        enabled: Bool,
        configured: Bool,
        healthMonitorEnabled: Bool
    ) {
        this.channelId = channelId
        this.accountId = accountId
        this.pluginId = pluginId
        this.origin = origin
        this.runtimeKind = runtimeKind
        this.compatibilityMode = compatibilityMode
        this.label = label
        this.detailLabel = detailLabel
        this.enabled = enabled
        this.configured = configured
        this.healthMonitorEnabled = healthMonitorEnabled
    }
}

public func gatewayBuiltinAdapterRegistrationProfiles(
    user: GatewayUserSettings,
    healthMonitorEnabled: Bool
): Array<GatewayAdapterRegistrationProfile> {
    let rows = ArrayList<GatewayAdapterRegistrationProfile>()
    let (feishuConfig, qqConfig, telegramConfig) = mergeGatewayUserSettings(user)

    let feishuCatalog = getGatewayChannelCatalogEntry("feishu")
    for (accountId in gatewayFeishuListAccountIds(feishuConfig)) {
        let resolved = gatewayFeishuResolveAccount(feishuConfig, accountId)
        rows.add(GatewayAdapterRegistrationProfile(
            "feishu",
            resolved.accountId,
            "feishu",
            "builtin",
            "builtin-adapter",
            "native-cangjie",
            match (feishuCatalog) { case Some(v) => v.label case None => "Feishu" },
            match (feishuCatalog) { case Some(v) => v.detailLabel case None => "Built-in Feishu adapter" },
            resolved.config.enabled,
            !resolved.config.appId.trimAscii().isEmpty() && !resolved.config.appSecret.trimAscii().isEmpty(),
            healthMonitorEnabled
        ))
    }

    let qqCatalog = getGatewayChannelCatalogEntry("qq")
    for (accountId in gatewayQqListAccountIds(qqConfig)) {
        let resolved = gatewayQqResolveAccount(qqConfig, accountId)
        rows.add(GatewayAdapterRegistrationProfile(
            "qq",
            resolved.accountId,
            "qq",
            "builtin",
            "builtin-adapter",
            "native-cangjie",
            match (qqCatalog) { case Some(v) => v.label case None => "QQ" },
            match (qqCatalog) { case Some(v) => v.detailLabel case None => "Built-in QQ adapter" },
            resolved.config.enabled,
            !resolved.config.appId.trimAscii().isEmpty() && !resolved.config.appSecret.trimAscii().isEmpty(),
            healthMonitorEnabled
        ))
    }

    let telegramCatalog = getGatewayChannelCatalogEntry("telegram")
    for (accountId in gatewayTelegramListAccountIds(telegramConfig)) {
        let resolved = gatewayTelegramResolveAccount(telegramConfig, accountId)
        rows.add(GatewayAdapterRegistrationProfile(
            "telegram",
            resolved.accountId,
            "telegram",
            "builtin",
            "builtin-adapter",
            "native-cangjie",
            match (telegramCatalog) { case Some(v) => v.label case None => "Telegram" },
            match (telegramCatalog) { case Some(v) => v.detailLabel case None => "Built-in Telegram adapter" },
            resolved.config.enabled,
            resolved.configured,
            healthMonitorEnabled
        ))
    }

    for ((channelId, fallbackLabel) in [("slack", "Slack"), ("discord", "Discord")]) {
        let builtinCfg = gatewayBuiltinExtraConfig(user, channelId)
        let builtinEnabled = gatewayBuiltinExtraBool(builtinCfg, "enabled", false)
        let builtinConfigured = gatewayBuiltinExtraConfigured(builtinCfg)
        let builtinCatalog = getGatewayChannelCatalogEntry(channelId)
        rows.add(GatewayAdapterRegistrationProfile(
            channelId,
            "default",
            channelId,
            "builtin",
            "builtin-adapter",
            "native-cangjie",
            match (builtinCatalog) { case Some(v) => v.label case None => fallbackLabel },
            match (builtinCatalog) { case Some(v) => v.detailLabel case None => "Built-in ${fallbackLabel} adapter" },
            builtinEnabled,
            builtinConfigured,
            healthMonitorEnabled
        ))
    }

    rows.toArray()
}
