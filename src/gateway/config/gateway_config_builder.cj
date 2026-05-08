package metis.gateway.config

import metis.core.config.{
    GatewayUserSettings,
    FeishuUserSettings,
    QQUserSettings,
    TelegramUserSettings,
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
import metis.gateway.{gatewayRuntimeEffectiveAuthPasswordString, gatewayRuntimeEffectiveAuthTokenString}
import metis.gateway.model.*

import std.collection.{ArrayList, HashMap}

import stdx.encoding.json.{JsonObject, JsonString, JsonValue}

private func gatewayBuilderBuiltinExtraConfig(user: GatewayUserSettings, channelId: String): JsonObject {
    let normalized = channelId.trimAscii().toAsciiLower()
    match (user.channelsExtra) {
        case Some(extra) =>
            match (extra.get(normalized)) {
                case Some(v) =>
                    try { v.asObject() } catch (_e: Exception) { JsonObject(HashMap<String, JsonValue>()) }
                case None => JsonObject(HashMap<String, JsonValue>())
            }
        case None => JsonObject(HashMap<String, JsonValue>())
    }
}

private func gatewayBuilderBuiltinExtraBool(cfg: JsonObject, key: String, defaultValue: Bool): Bool {
    match (cfg.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { defaultValue }
        case None => defaultValue
    }
}

private func gatewayBuilderBuiltinExtraString(cfg: JsonObject, key: String): String {
    match (cfg.get(key)) {
        case Some(v) =>
            try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func gatewayBuilderBuiltinExtraConfigured(cfg: JsonObject): Bool {
    if (gatewayBuilderBuiltinExtraBool(cfg, "configured", false)) {
        return true
    }
    for (key in ["token", "botToken", "appToken", "webhookUrl", "signingSecret", "channel", "guildId"]) {
        if (!gatewayBuilderBuiltinExtraString(cfg, key).isEmpty()) {
            return true
        }
    }
    false
}

private func gatewayBuilderPortToUInt16(p: Int64, fallback: UInt16): UInt16 {
    if (p <= 0 || p > 65535) {
        return fallback
    }
    UInt16(p)
}

private func gatewayBuilderNonEmptyJsonString(v: String): Option<JsonValue> {
    let trimmed = v.trimAscii()
    if (trimmed.isEmpty()) {
        return None<JsonValue>
    }
    Some<JsonValue>(JsonString(trimmed))
}

private func buildGatewayTlsConfig(user: GatewayTlsUserSettings): GatewayTlsConfig {
    GatewayTlsConfig(
        enabled: user.enabled,
        autoGenerate: user.autoGenerate,
        certPath: user.certPath,
        keyPath: user.keyPath,
        caPath: user.caPath
    )
}

private func buildGatewayDiscoveryConfig(user: GatewayDiscoveryUserSettings): GatewayDiscoveryConfig {
    GatewayDiscoveryConfig(
        wideArea: GatewayWideAreaDiscoveryConfig(
            enabled: user.wideArea.enabled,
            domain: user.wideArea.domain
        ),
        mdns: GatewayMdnsDiscoveryConfig(mode: user.mdns.mode)
    )
}

private func buildGatewayControlUiConfig(user: GatewayControlUiUserSettings): GatewayControlUiConfig {
    GatewayControlUiConfig(
        enabled: user.enabled,
        basePath: user.basePath,
        root: user.root,
        allowedOrigins: user.allowedOrigins,
        dangerouslyAllowHostHeaderOriginFallback: user.dangerouslyAllowHostHeaderOriginFallback,
        allowInsecureAuth: user.allowInsecureAuth,
        dangerouslyDisableDeviceAuth: user.dangerouslyDisableDeviceAuth
    )
}

private func buildGatewayAuthConfig(user: GatewayAuthUserSettings): GatewayAuthConfig {
    let authToken = gatewayRuntimeEffectiveAuthTokenString(user.token)
    let authPassword = gatewayRuntimeEffectiveAuthPasswordString(user.password)
    GatewayAuthConfig(
        mode: user.mode,
        token: gatewayBuilderNonEmptyJsonString(authToken),
        password: gatewayBuilderNonEmptyJsonString(authPassword),
        allowTailscale: user.allowTailscale,
        rateLimit: GatewayAuthRateLimitConfig(
            maxAttempts: user.rateLimit.maxAttempts,
            windowMs: user.rateLimit.windowMs,
            lockoutMs: user.rateLimit.lockoutMs,
            exemptLoopback: user.rateLimit.exemptLoopback
        ),
        trustedProxy: GatewayTrustedProxyConfig(
            userHeader: user.trustedProxy.userHeader,
            requiredHeaders: user.trustedProxy.requiredHeaders,
            allowUsers: user.trustedProxy.allowUsers
        )
    )
}

private func buildGatewayTailscaleConfig(user: GatewayTailscaleUserSettings): GatewayTailscaleConfig {
    GatewayTailscaleConfig(mode: user.mode, resetOnExit: user.resetOnExit)
}

private func buildGatewayRemoteConfig(user: GatewayRemoteUserSettings): GatewayRemoteConfig {
    GatewayRemoteConfig(
        enabled: user.enabled,
        url: user.url,
        transport: user.transport,
        token: gatewayBuilderNonEmptyJsonString(user.token),
        password: gatewayBuilderNonEmptyJsonString(user.password),
        tlsFingerprint: user.tlsFingerprint,
        sshTarget: user.sshTarget,
        sshIdentity: user.sshIdentity
    )
}

private func buildGatewayReloadConfig(user: GatewayReloadUserSettings): GatewayReloadConfig {
    GatewayReloadConfig(
        mode: user.mode,
        debounceMs: user.debounceMs,
        deferralTimeoutMs: user.deferralTimeoutMs
    )
}

private func buildGatewayHttpConfig(user: GatewayHttpUserSettings): GatewayHttpConfig {
    GatewayHttpConfig(
        endpoints: GatewayHttpEndpointsConfig(
            chatCompletions: GatewayHttpChatCompletionsConfig(
                enabled: user.endpoints.chatCompletions.enabled,
                maxBodyBytes: user.endpoints.chatCompletions.maxBodyBytes,
                maxImageParts: user.endpoints.chatCompletions.maxImageParts,
                maxTotalImageBytes: user.endpoints.chatCompletions.maxTotalImageBytes,
                images: GatewayHttpChatCompletionsImagesConfig(
                    allowUrl: user.endpoints.chatCompletions.images.allowUrl,
                    urlAllowlist: user.endpoints.chatCompletions.images.urlAllowlist,
                    allowedMimes: user.endpoints.chatCompletions.images.allowedMimes,
                    maxBytes: user.endpoints.chatCompletions.images.maxBytes,
                    maxRedirects: user.endpoints.chatCompletions.images.maxRedirects,
                    timeoutMs: user.endpoints.chatCompletions.images.timeoutMs
                )
            ),
            responses: GatewayHttpResponsesConfig(
                enabled: user.endpoints.responses.enabled,
                maxBodyBytes: user.endpoints.responses.maxBodyBytes,
                maxUrlParts: user.endpoints.responses.maxUrlParts,
                files: GatewayHttpResponsesFilesConfig(
                    allowUrl: user.endpoints.responses.files.allowUrl,
                    urlAllowlist: user.endpoints.responses.files.urlAllowlist,
                    allowedMimes: user.endpoints.responses.files.allowedMimes,
                    maxBytes: user.endpoints.responses.files.maxBytes,
                    maxChars: user.endpoints.responses.files.maxChars,
                    maxRedirects: user.endpoints.responses.files.maxRedirects,
                    timeoutMs: user.endpoints.responses.files.timeoutMs,
                    pdf: GatewayHttpResponsesPdfConfig(
                        maxPages: user.endpoints.responses.files.pdf.maxPages,
                        maxPixels: user.endpoints.responses.files.pdf.maxPixels,
                        minTextChars: user.endpoints.responses.files.pdf.minTextChars
                    )
                ),
                images: GatewayHttpResponsesImagesConfig(
                    allowUrl: user.endpoints.responses.images.allowUrl,
                    urlAllowlist: user.endpoints.responses.images.urlAllowlist,
                    allowedMimes: user.endpoints.responses.images.allowedMimes,
                    maxBytes: user.endpoints.responses.images.maxBytes,
                    maxRedirects: user.endpoints.responses.images.maxRedirects,
                    timeoutMs: user.endpoints.responses.images.timeoutMs
                )
            )
        ),
        securityHeaders: GatewayHttpSecurityHeadersConfig(
            strictTransportSecurity: gatewayBuilderNonEmptyJsonString(user.securityHeaders.strictTransportSecurity)
        )
    )
}

private func buildGatewayPushConfig(user: GatewayPushUserSettings): GatewayPushConfig {
    GatewayPushConfig(
        apns: GatewayPushApnsConfig(
            relay: GatewayPushApnsRelayConfig(
                baseUrl: user.apns.relay.baseUrl,
                timeoutMs: user.apns.relay.timeoutMs
            )
        )
    )
}

private func buildGatewayNodesConfig(user: GatewayNodesUserSettings): GatewayNodesConfig {
    GatewayNodesConfig(
        browser: GatewayNodesBrowserConfig(
            mode: user.browser.mode,
            node: user.browser.node
        ),
        allowCommands: user.allowCommands,
        denyCommands: user.denyCommands
    )
}

private func buildGatewayCanvasConfig(user: GatewayCanvasHostUserSettings): GatewayCanvasHostConfig {
    GatewayCanvasHostConfig(
        enabled: user.enabled,
        root: user.root,
        port: user.port,
        liveReload: user.liveReload
    )
}

private func buildGatewayTalkConfig(user: GatewayTalkUserSettings): GatewayTalkConfig {
    GatewayTalkConfig(
        provider: user.provider,
        providers: user.providers,
        interruptOnSpeech: user.interruptOnSpeech,
        silenceTimeoutMs: user.silenceTimeoutMs
    )
}

private func buildGatewayWebchatConfig(user: GatewayWebchatUserSettings): GatewayWebchatConfig {
    GatewayWebchatConfig(chatHistoryMaxChars: user.chatHistoryMaxChars)
}

private func mergeFeishu(fs: FeishuUserSettings): FeishuConfig {
    let receiveModeRaw = fs.receiveMode.toAsciiLower()
    let receiveMode = if (receiveModeRaw == "webhook") { "webhook" } else { "long_connect" }
    let groupSessionScopeRaw = fs.groupSessionScope.toAsciiLower()
    let groupSessionScope = if (
        groupSessionScopeRaw == "group_sender" ||
        groupSessionScopeRaw == "group_topic" ||
        groupSessionScopeRaw == "group_topic_sender"
    ) {
        groupSessionScopeRaw
    } else {
        "group"
    }
    let replyInThreadRaw = fs.replyInThread.toAsciiLower()
    let replyInThread = if (replyInThreadRaw == "enabled") { "enabled" } else { "disabled" }
    FeishuConfig(
        enabled: fs.enabled,
        streaming: fs.streaming.trimAscii(),
        blockStreaming: fs.blockStreaming,
        appId: fs.appId,
        appSecret: fs.appSecret,
        receiveMode: receiveMode,
        domain: fs.domain,
        botOpenId: fs.botOpenId,
        webhookHost: fs.webhookHost,
        webhookPort: gatewayBuilderPortToUInt16(fs.webhookPort, 3000u16),
        webhookPath: fs.webhookPath,
        verificationToken: fs.verificationToken,
        encryptKey: fs.encryptKey,
        groupSessionScope: groupSessionScope,
        replyInThread: replyInThread,
        requireSignatureHeaders: fs.requireSignatureHeaders,
        requestMaxSkewSeconds: fs.requestMaxSkewSeconds,
        policy: ChannelPolicyConfig()
    )
}

private func mergeQQ(qs: QQUserSettings): QQConfig {
    QQConfig(
        enabled: qs.enabled,
        streaming: qs.streaming.trimAscii(),
        blockStreaming: qs.blockStreaming,
        mode: "official_ws",
        webhookHost: qs.webhookHost,
        webhookPort: gatewayBuilderPortToUInt16(qs.webhookPort, 5701u16),
        webhookPath: qs.webhookPath,
        accessToken: "",
        requireAuthorizationHeader: true,
        onebotApiBaseUrl: qs.onebotApiBaseUrl,
        sendApiMode: "split",
        botQQ: qs.botQQ,
        dedupWindowSize: qs.dedupWindowSize,
        appId: qs.appId,
        appSecret: qs.appSecret,
        officialBotToken: "",
        officialTokenUrl: if (!qs.officialTokenUrl.trimAscii().isEmpty()) { qs.officialTokenUrl.trimAscii() } else { "https://bots.qq.com/app/getAppAccessToken" },
        officialGatewayUrl: if (!qs.officialGatewayUrl.trimAscii().isEmpty()) { qs.officialGatewayUrl.trimAscii() } else { "https://api.sgroup.qq.com/gateway" },
        officialWebsocketUrl: qs.officialWebsocketUrl.trimAscii(),
        officialAuthScheme: if (!qs.officialAuthScheme.trimAscii().isEmpty()) { qs.officialAuthScheme.trimAscii() } else { "QQBot" },
        officialIntents: qs.officialIntents,
        officialSendPrivateUrlTemplate: if (!qs.officialSendPrivateUrlTemplate.trimAscii().isEmpty()) { qs.officialSendPrivateUrlTemplate.trimAscii() } else { "https://api.sgroup.qq.com/v2/users/{peer_id}/messages" },
        officialSendGroupUrlTemplate: if (!qs.officialSendGroupUrlTemplate.trimAscii().isEmpty()) { qs.officialSendGroupUrlTemplate.trimAscii() } else { "https://api.sgroup.qq.com/v2/groups/{peer_id}/messages" },
        policy: ChannelPolicyConfig()
    )
}

private func mergeTelegram(user: GatewayUserSettings): TelegramConfig {
    let extra = gatewayBuilderBuiltinExtraConfig(user, "telegram")
    let botToken = if (!user.telegram.botToken.trimAscii().isEmpty()) {
        user.telegram.botToken.trimAscii()
    } else {
        gatewayBuilderBuiltinExtraString(extra, "botToken")
    }
    let webhookUrl = if (!user.telegram.webhookUrl.trimAscii().isEmpty()) {
        user.telegram.webhookUrl.trimAscii()
    } else {
        gatewayBuilderBuiltinExtraString(extra, "webhookUrl")
    }
    let webhookSecret = if (!user.telegram.webhookSecret.trimAscii().isEmpty()) {
        user.telegram.webhookSecret.trimAscii()
    } else {
        gatewayBuilderBuiltinExtraString(extra, "webhookSecret")
    }
    let policy = ChannelPolicyConfig(
        allowFrom: user.telegram.allowFrom,
        requireMentionInGroup: user.telegram.groupPolicy.trimAscii().toAsciiLower() != "open",
        enableDirect: user.telegram.dmPolicy.trimAscii().toAsciiLower() != "disabled",
        enableGroup: user.telegram.groupPolicy.trimAscii().toAsciiLower() != "disabled"
    )
    let customCommands = ArrayList<TelegramCustomCommandConfig>()
    for (one in user.telegram.customCommands) {
        customCommands.add(
            TelegramCustomCommandConfig(
                command: one.command.trimAscii(),
                description: one.description.trimAscii(),
                prompt: one.prompt.trimAscii(),
                reply: one.reply.trimAscii()
            )
        )
    }
    let telegramDefaultAccount = if (user.telegram.defaultAccount.trimAscii().isEmpty()) {
        "default"
    } else {
        user.telegram.defaultAccount.trimAscii()
    }
    TelegramConfig(
        accountId: telegramDefaultAccount,
        defaultAccount: telegramDefaultAccount,
        enabled: user.telegram.enabled || gatewayBuilderBuiltinExtraBool(extra, "enabled", false),
        botToken: botToken,
        tokenFile: user.telegram.tokenFile.trimAscii(),
        dmPolicy: user.telegram.dmPolicy.trimAscii(),
        allowFrom: user.telegram.allowFrom,
        defaultTo: user.telegram.defaultTo.trimAscii(),
        groupPolicy: user.telegram.groupPolicy.trimAscii(),
        groupAllowFrom: user.telegram.groupAllowFrom,
        groups: user.telegram.groups,
        direct: user.telegram.direct,
        dms: user.telegram.dms,
        accounts: user.telegram.accounts,
        commandsNative: user.telegram.commandsNative.trimAscii(),
        customCommands: customCommands.toArray(),
        replyToMode: user.telegram.replyToMode.trimAscii(),
        groupHistoryEnabled: user.telegram.groupHistoryEnabled,
        groupHistoryLimit: user.telegram.groupHistoryLimit,
        textChunkLimit: user.telegram.textChunkLimit,
        chunkMode: user.telegram.chunkMode.trimAscii(),
        streaming: user.telegram.streaming.trimAscii(),
        blockStreaming: user.telegram.blockStreaming,
        timeoutSeconds: user.telegram.timeoutSeconds,
        linkPreview: user.telegram.linkPreview,
        silent: user.telegram.silent,
        webhookUrl: webhookUrl,
        webhookSecret: webhookSecret,
        webhookCertPath: user.telegram.webhookCertPath.trimAscii(),
        webhookPath: user.telegram.webhookPath.trimAscii(),
        webhookHost: user.telegram.webhookHost.trimAscii(),
        webhookPort: gatewayBuilderPortToUInt16(user.telegram.webhookPort, 8787u16),
        webhookMaxBodyBytes: user.telegram.webhookMaxBodyBytes,
        webhookBodyTimeoutMs: user.telegram.webhookBodyTimeoutMs,
        webhookRateLimitWindowMs: user.telegram.webhookRateLimitWindowMs,
        webhookRateLimitMaxRequests: user.telegram.webhookRateLimitMaxRequests,
        trustedProxies: user.trustedProxies,
        allowRealIpFallback: user.allowRealIpFallback,
        apiRoot: user.telegram.apiRoot.trimAscii(),
        proxy: user.telegram.proxy.trimAscii(),
        reactionNotifications: user.telegram.reactionNotifications.trimAscii(),
        reactionLevel: user.telegram.reactionLevel.trimAscii(),
        ackReaction: user.telegram.ackReaction,
        removeAckAfterReply: user.telegram.removeAckAfterReply,
        configWrites: user.telegram.configWrites,
        actions: TelegramActionConfig(
            reactions: user.telegram.actions.reactions,
            sendMessage: user.telegram.actions.sendMessage,
            poll: user.telegram.actions.poll,
            deleteMessage: user.telegram.actions.deleteMessage,
            editMessage: user.telegram.actions.editMessage,
            pinMessage: user.telegram.actions.pinMessage,
            unpinMessage: user.telegram.actions.unpinMessage,
            photo: user.telegram.actions.photo,
            document: user.telegram.actions.document,
            audio: user.telegram.actions.audio,
            voice: user.telegram.actions.voice,
            video: user.telegram.actions.video,
            videoNote: user.telegram.actions.videoNote,
            sticker: user.telegram.actions.sticker,
            createForumTopic: user.telegram.actions.createForumTopic,
            editForumTopic: user.telegram.actions.editForumTopic,
            inlineKeyboard: user.telegram.actions.inlineKeyboard,
            callbackQuery: user.telegram.actions.callbackQuery
        ),
        inlineButtons: TelegramInlineButtonsConfig(
            scope: user.telegram.inlineButtons.scope,
            allowlist: user.telegram.inlineButtons.allowlist
        ),
        execApprovals: TelegramExecApprovalsConfig(
            enabled: user.telegram.execApprovals.enabled,
            approvers: user.telegram.execApprovals.approvers,
            agentFilter: user.telegram.execApprovals.agentFilter,
            sessionFilter: user.telegram.execApprovals.sessionFilter,
            target: user.telegram.execApprovals.target
        ),
        errorPolicy: TelegramErrorPolicyConfig(
            policy: user.telegram.errorPolicy.policy,
            cooldownMs: user.telegram.errorPolicy.cooldownMs,
            silentErrorReplies: user.telegram.errorPolicy.silentErrorReplies
        ),
        autoTopicLabel: TelegramAutoTopicLabelConfig(
            enabled: user.telegram.autoTopicLabel.enabled,
            strategy: user.telegram.autoTopicLabel.strategy,
            prompt: user.telegram.autoTopicLabel.prompt
        ),
        threadBindings: TelegramThreadBindingsConfig(
            enabled: user.telegram.threadBindings.enabled,
            spawnSubagentSessions: user.telegram.threadBindings.spawnSubagentSessions,
            spawnAcpSessions: user.telegram.threadBindings.spawnAcpSessions
        ),
        media: TelegramMediaConfig(
            downloadEnabled: user.telegram.media.downloadEnabled,
            mediaMaxBytes: user.telegram.media.mediaMaxBytes,
            allowedMimes: user.telegram.media.allowedMimes,
            outboundAllowUrl: user.telegram.media.outboundAllowUrl,
            outboundAllowLocalPath: user.telegram.media.outboundAllowLocalPath,
            outboundLocalRoots: user.telegram.media.outboundLocalRoots,
            trustedLocalFileRoots: user.telegram.media.trustedLocalFileRoots,
            albumPolicy: user.telegram.media.albumPolicy.trimAscii(),
            warnOnDownloadFailure: user.telegram.media.warnOnDownloadFailure
        ),
        network: TelegramNetworkConfig(
            autoSelectFamily: user.telegram.network.autoSelectFamily,
            dnsResultOrder: user.telegram.network.dnsResultOrder.trimAscii(),
            dangerouslyAllowPrivateNetwork: user.telegram.network.dangerouslyAllowPrivateNetwork,
            insecureSkipTlsVerify: user.telegram.network.insecureSkipTlsVerify,
            envProxyEnabled: user.telegram.network.envProxyEnabled,
            allowedUpdatesExtra: user.telegram.network.allowedUpdatesExtra,
            getFileRetryCount: user.telegram.network.getFileRetryCount
        ),
        policy: policy
    )
}

public func mergeGatewayUserSettings(user: GatewayUserSettings): (FeishuConfig, QQConfig, TelegramConfig) {
    (mergeFeishu(user.feishu), mergeQQ(user.qq), mergeTelegram(user))
}

public func buildGatewayConfigFromUserSettings(user: GatewayUserSettings): GatewayConfig {
    let (feishuCfg, qqCfg, telegramCfg) = mergeGatewayUserSettings(user)
    let policyByChannel = HashMap<String, ChannelPolicyConfig>()
    let defaultPolicy = ChannelPolicyConfig(
        allowFrom: [],
        requireMentionInGroup: true,
        enableDirect: true,
        enableGroup: true
    )
    policyByChannel["feishu"] = defaultPolicy
    policyByChannel["qq"] = defaultPolicy
    policyByChannel["telegram"] = defaultPolicy
    policyByChannel["slack"] = defaultPolicy
    policyByChannel["discord"] = defaultPolicy

    for (pe in user.gatewayPlugins) {
        if (!pe.enabled || pe.id.trimAscii().isEmpty()) {
            continue
        }
        match (GatewayChannelPluginRegistry.getById(pe.id)) {
            case Some(pl) =>
                for (cid in pl.declaredChannelIds()) {
                    if (!cid.trimAscii().isEmpty()) {
                        policyByChannel[cid] = defaultPolicy
                    }
                }
            case None => ()
        }
    }

    GatewayConfig(
        port: user.port,
        mode: user.mode,
        bind: user.bind,
        customBindHost: user.customBindHost,
        enabled: user.enabled,
        discovery: buildGatewayDiscoveryConfig(user.discovery),
        tls: buildGatewayTlsConfig(user.tls),
        controlUi: buildGatewayControlUiConfig(user.controlUi),
        auth: buildGatewayAuthConfig(user.auth),
        tailscale: buildGatewayTailscaleConfig(user.tailscale),
        remote: buildGatewayRemoteConfig(user.remote),
        reload: buildGatewayReloadConfig(user.reload),
        http: buildGatewayHttpConfig(user.http),
        push: buildGatewayPushConfig(user.push),
        nodes: buildGatewayNodesConfig(user.nodes),
        trustedProxies: user.trustedProxies,
        allowRealIpFallback: user.allowRealIpFallback,
        policyByChannel: policyByChannel,
        canvas: buildGatewayCanvasConfig(user.canvas),
        talk: buildGatewayTalkConfig(user.talk),
        feishu: feishuCfg,
        qq: qqCfg,
        telegram: telegramCfg,
        webchat: buildGatewayWebchatConfig(user.webchat),
        channelHealthCheckMinutes: user.channelHealthCheckMinutes,
        channelStaleEventThresholdMinutes: user.channelStaleEventThresholdMinutes,
        channelMaxRestartsPerHour: user.channelMaxRestartsPerHour
    )
}
