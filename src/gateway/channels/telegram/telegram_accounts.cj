package metis.gateway.channels.telegram

import metis.gateway.model.TelegramConfig

import std.collection.{ArrayList, HashSet}
import stdx.encoding.json.JsonObject

public class TelegramResolvedAccount {
    public let accountId: String
    public let config: TelegramConfig
    public let explicitAccount: Bool
    public let configured: Bool

    public init(
        accountId: String,
        config: TelegramConfig,
        explicitAccount!: Bool = false,
        configured!: Bool = false
    ) {
        this.accountId = gatewayTelegramNormalizeAccountId(accountId)
        this.config = config
        this.explicitAccount = explicitAccount
        this.configured = configured
    }
}

public func gatewayTelegramNormalizeAccountId(raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return "default"
    }
    let lower = trimmed.toAsciiLower()
    for (prefix in ["telegram:", "tg:"]) {
        if (lower.startsWith(prefix)) {
            let suffix = trimmed[prefix.size..].trimAscii()
            return if (suffix.isEmpty()) { "default" } else { suffix }
        }
    }
    trimmed
}

public func gatewayTelegramDefaultAccountId(config: TelegramConfig): String {
    gatewayTelegramNormalizeAccountId(config.defaultAccount)
}

public func gatewayTelegramListAccountIds(config: TelegramConfig): Array<String> {
    let out = ArrayList<String>()
    let seen = HashSet<String>()
    let defaultAccount = gatewayTelegramDefaultAccountId(config)
    out.add(defaultAccount)
    seen.add(defaultAccount)
    match (config.accounts) {
        case Some(accounts) =>
            for (raw in accounts.getFields().keys()) {
                let id = gatewayTelegramNormalizeAccountId(raw)
                if (!seen.contains(id)) {
                    out.add(id)
                    seen.add(id)
                }
            }
        case None => ()
    }
    out.toArray()
}

public func gatewayTelegramResolveAccount(config: TelegramConfig, accountId: String): TelegramResolvedAccount {
    let normalized = if (accountId.trimAscii().isEmpty()) {
        gatewayTelegramDefaultAccountId(config)
    } else {
        gatewayTelegramNormalizeAccountId(accountId)
    }
    let accountConfig = gatewayTelegramAccountOverride(config, normalized)
    let explicitAccount = accountConfig.isSome()
    let overrideObj = accountConfig ?? JsonObject()
    let merged = gatewayTelegramMergedConfig(config, normalized, overrideObj)
    TelegramResolvedAccount(
        normalized,
        merged,
        explicitAccount: explicitAccount,
        configured: !merged.botToken.trimAscii().isEmpty() || !merged.tokenFile.trimAscii().isEmpty()
    )
}

public func gatewayTelegramConfigForAccount(config: TelegramConfig, accountId: String): TelegramConfig {
    gatewayTelegramResolveAccount(config, accountId).config
}

private func gatewayTelegramAccountOverride(config: TelegramConfig, accountId: String): Option<JsonObject> {
    match (config.accounts) {
        case Some(accounts) =>
            match (accounts.get(accountId)) {
                case Some(value) => try { Some(value.asObject()) } catch (_: Exception) { None }
                case None =>
                    if (accountId == "default") {
                        let raw = match (accounts.get("telegram:default")) {
                            case Some(v) => Some(v)
                            case None => accounts.get("tg:default")
                        }
                        match (raw) {
                            case Some(value) => try { Some(value.asObject()) } catch (_: Exception) { None }
                            case None => None
                        }
                    } else {
                        let raw = match (accounts.get("telegram:${accountId}")) {
                            case Some(v) => Some(v)
                            case None => accounts.get("tg:${accountId}")
                        }
                        match (raw) {
                            case Some(value) => try { Some(value.asObject()) } catch (_: Exception) { None }
                            case None => None
                        }
                    }
            }
        case None => None
    }
}

private func gatewayTelegramString(obj: JsonObject, keys: Array<String>, fallback: String): String {
    for (key in keys) {
        match (obj.get(key)) {
            case Some(value) =>
                try {
                    return value.asString().getValue()
                } catch (_: Exception) {
                    ()
                }
            case None => ()
        }
    }
    fallback
}

private func gatewayTelegramBool(obj: JsonObject, key: String, fallback: Bool): Bool {
    match (obj.get(key)) {
        case Some(value) =>
            try { value.asBool().getValue() } catch (_: Exception) { fallback }
        case None => fallback
    }
}

private func gatewayTelegramObject(obj: JsonObject, key: String, fallback: Option<JsonObject>): Option<JsonObject> {
    match (obj.get(key)) {
        case Some(value) => try { Some(value.asObject()) } catch (_: Exception) { fallback }
        case None => fallback
    }
}

private func gatewayTelegramMergedConfig(base: TelegramConfig, accountId: String, overrideObj: JsonObject): TelegramConfig {
    TelegramConfig(
        accountId: accountId,
        defaultAccount: gatewayTelegramDefaultAccountId(base),
        enabled: gatewayTelegramBool(overrideObj, "enabled", base.enabled),
        botToken: gatewayTelegramString(overrideObj, ["botToken", "bot_token"], base.botToken),
        tokenFile: gatewayTelegramString(overrideObj, ["tokenFile", "token_file"], base.tokenFile),
        dmPolicy: gatewayTelegramString(overrideObj, ["dmPolicy", "dm_policy"], base.dmPolicy),
        allowFrom: base.allowFrom,
        defaultTo: gatewayTelegramString(overrideObj, ["defaultTo", "default_to"], base.defaultTo),
        groupPolicy: gatewayTelegramString(overrideObj, ["groupPolicy", "group_policy"], base.groupPolicy),
        groupAllowFrom: base.groupAllowFrom,
        groups: gatewayTelegramObject(overrideObj, "groups", base.groups),
        direct: gatewayTelegramObject(overrideObj, "direct", base.direct),
        dms: gatewayTelegramObject(overrideObj, "dms", base.dms),
        accounts: base.accounts,
        commandsNative: base.commandsNative,
        customCommands: base.customCommands,
        replyToMode: base.replyToMode,
        groupHistoryEnabled: base.groupHistoryEnabled,
        groupHistoryLimit: base.groupHistoryLimit,
        textChunkLimit: base.textChunkLimit,
        chunkMode: base.chunkMode,
        streaming: gatewayTelegramString(overrideObj, ["streaming"], base.streaming),
        blockStreaming: gatewayTelegramBool(overrideObj, "blockStreaming", base.blockStreaming),
        timeoutSeconds: base.timeoutSeconds,
        linkPreview: base.linkPreview,
        silent: base.silent,
        webhookUrl: gatewayTelegramString(overrideObj, ["webhookUrl", "webhook_url"], base.webhookUrl),
        webhookSecret: gatewayTelegramString(overrideObj, ["webhookSecret", "webhook_secret"], base.webhookSecret),
        webhookCertPath: gatewayTelegramString(overrideObj, ["webhookCertPath", "webhook_cert_path"], base.webhookCertPath),
        webhookPath: gatewayTelegramString(overrideObj, ["webhookPath", "webhook_path"], base.webhookPath),
        webhookHost: gatewayTelegramString(overrideObj, ["webhookHost", "webhook_host"], base.webhookHost),
        webhookPort: base.webhookPort,
        webhookMaxBodyBytes: base.webhookMaxBodyBytes,
        webhookBodyTimeoutMs: base.webhookBodyTimeoutMs,
        webhookRateLimitWindowMs: base.webhookRateLimitWindowMs,
        webhookRateLimitMaxRequests: base.webhookRateLimitMaxRequests,
        trustedProxies: base.trustedProxies,
        allowRealIpFallback: base.allowRealIpFallback,
        apiRoot: gatewayTelegramString(overrideObj, ["apiRoot", "api_root"], base.apiRoot),
        proxy: gatewayTelegramString(overrideObj, ["proxy"], base.proxy),
        reactionNotifications: base.reactionNotifications,
        reactionLevel: base.reactionLevel,
        ackReaction: base.ackReaction,
        removeAckAfterReply: base.removeAckAfterReply,
        configWrites: base.configWrites,
        actions: base.actions,
        inlineButtons: base.inlineButtons,
        execApprovals: base.execApprovals,
        errorPolicy: base.errorPolicy,
        autoTopicLabel: base.autoTopicLabel,
        threadBindings: base.threadBindings,
        media: base.media,
        network: base.network,
        policy: base.policy
    )
}
