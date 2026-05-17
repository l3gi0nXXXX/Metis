package metis.gateway.runtime

import metis.core.config.{
    CliConfig,
    GatewayUserSettings,
    GatewaySessionUserSettings,
    FeishuUserSettings,
    QQUserSettings,
    GatewayTlsUserSettings,
    GatewayDiscoveryUserSettings,
    GatewayControlUiUserSettings,
    GatewayAuthUserSettings,
    GatewayTailscaleUserSettings,
    GatewayRemoteUserSettings,
    GatewayReloadUserSettings,
    GatewayHttpUserSettings,
    GatewayPushUserSettings,
    GatewayNodesUserSettings,
    GatewayCanvasHostUserSettings,
    GatewayTalkUserSettings,
    GatewayWebchatUserSettings
}
import metis.gateway.channels.feishu.FeishuAdapter
import metis.gateway.channels.qq.QQAdapter
import metis.gateway.channels.telegram.gatewayTelegramConfigForAccount
import metis.gateway.channels.telegram.TelegramAdapter
import metis.gateway.channels.builtin.GenericBuiltinChannelAdapter
import metis.gateway.{gatewayRuntimeEffectiveAuthPasswordString, gatewayRuntimeEffectiveAuthTokenString}
import metis.gateway.config.{buildGatewayConfigFromUserSettings, ensureInstalledGatewayPluginsRegistered, gatewayBuiltinAdapterRegistrationProfiles, gatewayBuiltinExtraBool, gatewayBuiltinExtraConfig, gatewayBuiltinExtraConfigured, gatewayPreparedPluginAdapterRegistrations, GatewayChannelPluginRegistry, mergeGatewayUserSettings}
import metis.cron.registerGatewayCronRunUnified
import metis.gateway.core.{
    GatewayRouter,
    GatewayService,
    gatewayLogProcessMemory,
    gatewayBuildSessionTranscriptEventPayload,
    gatewayFindSessionConversationViewForUser,
    gatewayMigrateLegacyGatewaySessionsIfNeeded,
    gatewayPersistedSessionsRootForUser
}
import metis.gateway.model.*

import magic.log.LogUtils

import std.collection.HashMap
import std.convert.Parsable
import std.time.DateTime
import stdx.encoding.json.{JsonObject, JsonString, JsonValue}

private func gatewayConfigFactoryNowMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000
}

private func gatewayConfigFactoryTimingLog(step: String, startMs: Int64): Unit {
    let elapsedMs = gatewayConfigFactoryNowMs() - startMs
    LogUtils.info("Gateway.factory.timing: step=${step} elapsedMs=${elapsedMs}")
    gatewayLogProcessMemory("factory:${step}", note: "elapsedMs=${elapsedMs}")
}

private func matchWebhookPort(raw: String, fallback: UInt16): UInt16 {
    match (raw) {
        case "80" => 80u16
        case "443" => 443u16
        case "3000" => 3000u16
        case "3001" => 3001u16
        case "8080" => 8080u16
        case "8081" => 8081u16
        case "5700" => 5700u16
        case "5701" => 5701u16
        case _ => fallback
    }
}

private func mergeGatewaySession(ss: GatewaySessionUserSettings): (String, Bool) {
    (ss.dmScope, ss.persistenceEnabled)
}

/**
 * 是否至少有一条可运行的渠道：内置飞书/QQ 或已启用的扩展插件项。
 */
public func gatewayHasAnyEnabledChannel(user: GatewayUserSettings): Bool {
    let (fCfg, qCfg, tCfg) = mergeGatewayUserSettings(user)
    if (fCfg.enabled || qCfg.enabled || tCfg.enabled) {
        return true
    }
    for (builtinId in ["slack", "discord"]) {
        let builtinCfg = gatewayBuiltinExtraConfig(user, builtinId)
        if (gatewayBuiltinExtraBool(builtinCfg, "enabled", false)) {
            return true
        }
    }
    for (p in user.gatewayPlugins) {
        if (p.enabled && !p.id.trimAscii().isEmpty()) {
            return true
        }
    }
    false
}

/**
 * 组装网关：路由策略、Agent 桥、飞书与 QQ 适配器（按合并后的配置注册），并装配已注册的 `GatewayChannelPlugin`。
 * 扩展渠道配置建议放在 `gateway.channelsExtra.<pluginId>`。
 */
public func buildGatewayServiceFromUserSettings(user: GatewayUserSettings): (GatewayService, FeishuAdapter) {
    let startMs = gatewayConfigFactoryNowMs()
    gatewayInstallOpenClawCompatHostLifecycleHooks()
    ensureInstalledGatewayPluginsRegistered()
    gatewayConfigFactoryTimingLog("plugins-registered", startMs)
    gatewayPrimeConfiguredChannelBindings(user)
    gatewayConfigFactoryTimingLog("bindings-primed", startMs)
    let cfg = buildGatewayConfigFromUserSettings(user)
    gatewayConfigFactoryTimingLog("config-built", startMs)

    let (dmScopeRaw, _persistSessions) = mergeGatewaySession(user.session)
    let router = GatewayRouter(cfg.policyByChannel, dmScope: dmScopeRaw)
    let sessionRoot = gatewayPersistedSessionsRootForUser(user)
    gatewayMigrateLegacyGatewaySessionsIfNeeded(sessionRoot)
    gatewayConfigFactoryTimingLog("session-root-ready", startMs)
    let gateway = GatewayService(
        router,
        transcriptPublisher: Some({ context, delta, entryKind, lastRole =>
            let conversation = gatewayFindSessionConversationViewForUser(user, context.sessionKey)
            let payload = gatewayBuildSessionTranscriptEventPayload(
                context.sessionKey,
                entryKind,
                conversation: conversation,
                deliveryTarget: context.deliveryTarget,
                detail: "inbound-transcript-appended",
                delta: delta,
                lastRole: lastRole
            )
            let _ = gatewayServerPublishSessionTranscriptEvent(payload, detail: "inbound-transcript-appended")
        })
    )
    gatewayConfigFactoryTimingLog("gateway-service-created", startMs)

    let feishu = FeishuAdapter(config: cfg.feishu, accountId: cfg.feishu.accountId)
    for (profile in gatewayBuiltinAdapterRegistrationProfiles(user, cfg.channelHealthCheckMinutes > 0)) {
        if (profile.channelId == "feishu") {
            if (!profile.enabled || !profile.configured) {
                continue
            }
            let adapter = if (profile.accountId == cfg.feishu.accountId) {
                feishu
            } else {
                FeishuAdapter(config: cfg.feishu, accountId: profile.accountId)
            }
            gateway.registerAdapter(
                adapter,
                channelId: profile.channelId,
                accountId: profile.accountId,
                pluginId: profile.pluginId,
                origin: profile.origin,
                runtimeKind: profile.runtimeKind,
                compatibilityMode: profile.compatibilityMode,
                label: profile.label,
                detailLabel: profile.detailLabel,
                enabled: profile.enabled,
                configured: profile.configured,
                healthMonitorEnabled: profile.healthMonitorEnabled
            )
        } else if (profile.channelId == "qq") {
            if (!profile.enabled || !profile.configured) {
                continue
            }
            gateway.registerAdapter(
                QQAdapter(config: cfg.qq, accountId: profile.accountId),
                channelId: profile.channelId,
                accountId: profile.accountId,
                pluginId: profile.pluginId,
                origin: profile.origin,
                runtimeKind: profile.runtimeKind,
                compatibilityMode: profile.compatibilityMode,
                label: profile.label,
                detailLabel: profile.detailLabel,
                enabled: profile.enabled,
                configured: profile.configured,
                healthMonitorEnabled: profile.healthMonitorEnabled
            )
        } else if (profile.channelId == "telegram") {
            if (!profile.enabled || !profile.configured) {
                continue
            }
            gateway.registerAdapter(
                TelegramAdapter(config: gatewayTelegramConfigForAccount(cfg.telegram, profile.accountId), registerNativeCommandsOnStart: true),
                channelId: profile.channelId,
                accountId: profile.accountId,
                pluginId: profile.pluginId,
                origin: profile.origin,
                runtimeKind: profile.runtimeKind,
                compatibilityMode: profile.compatibilityMode,
                label: profile.label,
                detailLabel: profile.detailLabel,
                enabled: profile.enabled,
                configured: profile.configured,
                healthMonitorEnabled: profile.healthMonitorEnabled
            )
        } else {
            gateway.registerAdapter(
                GenericBuiltinChannelAdapter(
                    profile.channelId,
                    label: profile.label,
                    configured: profile.configured
                ),
                channelId: profile.channelId,
                accountId: profile.accountId,
                pluginId: profile.pluginId,
                origin: profile.origin,
                runtimeKind: profile.runtimeKind,
                compatibilityMode: profile.compatibilityMode,
                label: profile.label,
                detailLabel: profile.detailLabel,
                enabled: profile.enabled,
                configured: profile.configured,
                healthMonitorEnabled: profile.healthMonitorEnabled
            )
        }
    }
    gatewayConfigFactoryTimingLog("builtin-adapters-registered", startMs)

    let extra = user.channelsExtra
    for (pe in user.gatewayPlugins) {
        if (!pe.enabled || pe.id.trimAscii().isEmpty()) {
            continue
        }
        let pid = pe.id.trimAscii()
        match (GatewayChannelPluginRegistry.getById(pid)) {
            case Some(pl) =>
                for (prepared in gatewayPreparedPluginAdapterRegistrations(extra, pid, pl, cfg.channelHealthCheckMinutes > 0)) {
                    gateway.registerAdapter(
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
            case None =>
                LogUtils.info(
                    "Gateway: gatewayPlugins 项 id='${pid}' 未找到可用插件（请确认已安装到 ~/.metis/gateway-plugins，并包含插件 manifest + gatewayRuntime）。"
                )
        }
    }
    gatewayConfigFactoryTimingLog("plugin-adapters-registered", startMs)

    registerGatewayCronRunUnified(gatewayCronRunUnified)
    gatewayConfigFactoryTimingLog("service-build-total", startMs)
    return (gateway, feishu)
}
