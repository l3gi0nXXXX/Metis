package metis.gateway.config

import metis.core.config.GatewayUserSettings

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

    let feishuCatalog = getGatewayChannelCatalogEntry("feishu")
    rows.add(GatewayAdapterRegistrationProfile(
        "feishu",
        "feishu:default",
        "feishu",
        "builtin",
        "builtin-adapter",
        "native-cangjie",
        match (feishuCatalog) { case Some(v) => v.label case None => "Feishu" },
        match (feishuCatalog) { case Some(v) => v.detailLabel case None => "Built-in Feishu adapter" },
        user.feishu.enabled,
        !user.feishu.appId.trimAscii().isEmpty(),
        healthMonitorEnabled
    ))

    let qqCatalog = getGatewayChannelCatalogEntry("qq")
    rows.add(GatewayAdapterRegistrationProfile(
        "qq",
        "qq:default",
        "qq",
        "builtin",
        "builtin-adapter",
        "native-cangjie",
        match (qqCatalog) { case Some(v) => v.label case None => "QQ" },
        match (qqCatalog) { case Some(v) => v.detailLabel case None => "Built-in QQ adapter" },
        user.qq.enabled,
        !(user.qq.appId.trimAscii().isEmpty() || user.qq.appSecret.trimAscii().isEmpty()),
        healthMonitorEnabled
    ))

    let telegramCatalog = getGatewayChannelCatalogEntry("telegram")
    rows.add(GatewayAdapterRegistrationProfile(
        "telegram",
        "telegram:default",
        "telegram",
        "builtin",
        "builtin-adapter",
        "native-cangjie",
        match (telegramCatalog) { case Some(v) => v.label case None => "Telegram" },
        match (telegramCatalog) { case Some(v) => v.detailLabel case None => "Built-in Telegram adapter" },
        user.telegram.enabled,
        !(user.telegram.botToken.trimAscii().isEmpty() && user.telegram.tokenFile.trimAscii().isEmpty() && user.telegram.webhookUrl.trimAscii().isEmpty()),
        healthMonitorEnabled
    ))

    for ((channelId, fallbackLabel) in [("slack", "Slack"), ("discord", "Discord")]) {
        let builtinCfg = gatewayBuiltinExtraConfig(user, channelId)
        let builtinEnabled = gatewayBuiltinExtraBool(builtinCfg, "enabled", false)
        let builtinConfigured = gatewayBuiltinExtraConfigured(builtinCfg)
        let builtinCatalog = getGatewayChannelCatalogEntry(channelId)
        rows.add(GatewayAdapterRegistrationProfile(
            channelId,
            "${channelId}:default",
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
