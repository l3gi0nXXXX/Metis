package metis.gateway.channels.feishu

import metis.gateway.model.{ChannelPolicyConfig, FeishuConfig, FeishuMediaConfig}

import std.collection.{ArrayList, HashSet}
import std.convert.Parsable
import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject, JsonString, JsonValue}

public class FeishuResolvedAccount {
    public let accountId: String
    public let config: FeishuConfig
    public let explicitAccount: Bool
    public let credentialSource: String

    public init(accountId: String, config: FeishuConfig, explicitAccount!: Bool = false, credentialSource!: String = "top-level") {
        this.accountId = gatewayFeishuNormalizeAccountId(accountId)
        this.config = config
        this.explicitAccount = explicitAccount
        this.credentialSource = credentialSource.trimAscii()
    }
}

public func gatewayFeishuNormalizeAccountId(raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) { "default" } else { trimmed }
}

public func gatewayFeishuDefaultAccountId(config: FeishuConfig): String {
    gatewayFeishuNormalizeAccountId(config.defaultAccount)
}

public func gatewayFeishuListAccountIds(config: FeishuConfig): Array<String> {
    let out = ArrayList<String>()
    let seen = HashSet<String>()
    let defaultAccount = gatewayFeishuDefaultAccountId(config)
    out.add(defaultAccount)
    seen.add(defaultAccount)
    match (config.accounts) {
        case Some(accounts) =>
            for (raw in accounts.getFields().keys()) {
                let id = gatewayFeishuNormalizeAccountId(raw)
                if (!seen.contains(id)) {
                    out.add(id)
                    seen.add(id)
                }
            }
        case None => ()
    }
    out.toArray()
}

public func gatewayFeishuResolveAccount(config: FeishuConfig, accountId: String): FeishuResolvedAccount {
    let normalized = if (accountId.trimAscii().isEmpty()) {
        gatewayFeishuDefaultAccountId(config)
    } else {
        gatewayFeishuNormalizeAccountId(accountId)
    }
    let accountConfig = gatewayFeishuAccountOverride(config, normalized)
    let explicitAccount = accountConfig.isSome()
    let overrideObj = accountConfig ?? JsonObject()
    let credentialSource = if (
        gatewayFeishuHasString(overrideObj, ["appId", "app_id"]) ||
        gatewayFeishuHasString(overrideObj, ["appSecret", "app_secret"])
    ) {
        "account"
    } else if (!config.appId.trimAscii().isEmpty() || !config.appSecret.trimAscii().isEmpty()) {
        "top-level"
    } else {
        "missing"
    }
    let merged = FeishuConfig(
        accountId: normalized,
        defaultAccount: gatewayFeishuDefaultAccountId(config),
        enabled: gatewayFeishuBool(overrideObj, "enabled", config.enabled),
        streaming: gatewayFeishuString(overrideObj, ["streaming"], config.streaming),
        blockStreaming: gatewayFeishuBool(overrideObj, "blockStreaming", config.blockStreaming),
        appId: gatewayFeishuString(overrideObj, ["appId", "app_id"], config.appId),
        appSecret: gatewayFeishuString(overrideObj, ["appSecret", "app_secret"], config.appSecret),
        accounts: config.accounts,
        receiveMode: gatewayFeishuReceiveMode(gatewayFeishuString(overrideObj, ["receiveMode", "receive_mode"], config.receiveMode)),
        domain: gatewayFeishuString(overrideObj, ["domain"], config.domain),
        botOpenId: gatewayFeishuString(overrideObj, ["botOpenId", "bot_open_id"], config.botOpenId),
        webhookHost: gatewayFeishuString(overrideObj, ["webhookHost", "webhook_host"], config.webhookHost),
        webhookPort: gatewayFeishuUInt16(overrideObj, ["webhookPort", "webhook_port"], config.webhookPort),
        webhookPath: gatewayFeishuString(overrideObj, ["webhookPath", "webhook_path"], config.webhookPath),
        verificationToken: gatewayFeishuString(overrideObj, ["verificationToken", "verification_token"], config.verificationToken),
        encryptKey: gatewayFeishuString(overrideObj, ["encryptKey", "encrypt_key"], config.encryptKey),
        groupSessionScope: gatewayFeishuGroupSessionScope(gatewayFeishuString(overrideObj, ["groupSessionScope", "group_session_scope"], config.groupSessionScope)),
        threadSession: gatewayFeishuBool(overrideObj, "threadSession", config.threadSession),
        groups: gatewayFeishuObjectOption(overrideObj, "groups", config.groups),
        groupPolicy: gatewayFeishuGroupPolicy(gatewayFeishuString(overrideObj, ["groupPolicy", "group_policy"], config.groupPolicy)),
        groupAllowFrom: gatewayFeishuStringArray(overrideObj, "groupAllowFrom", config.groupAllowFrom),
        requireMention: gatewayFeishuBool(overrideObj, "requireMention", config.requireMention),
        allowBots: gatewayFeishuBool(overrideObj, "allowBots", config.allowBots),
        replyInThread: gatewayFeishuReplyInThread(gatewayFeishuString(overrideObj, ["replyInThread", "reply_in_thread"], config.replyInThread)),
        requireSignatureHeaders: gatewayFeishuBool(overrideObj, "requireSignatureHeaders", config.requireSignatureHeaders),
        requestMaxSkewSeconds: gatewayFeishuInt(overrideObj, ["requestMaxSkewSeconds", "request_max_skew_seconds"], config.requestMaxSkewSeconds),
        media: gatewayFeishuMedia(overrideObj, config.media),
        policy: ChannelPolicyConfig(
            allowFrom: [],
            requireMentionInGroup: gatewayFeishuBool(overrideObj, "requireMention", config.requireMention),
            enableDirect: true,
            enableGroup: gatewayFeishuGroupPolicy(gatewayFeishuString(overrideObj, ["groupPolicy", "group_policy"], config.groupPolicy)) != "disabled"
        )
    )
    FeishuResolvedAccount(normalized, merged, explicitAccount: explicitAccount, credentialSource: credentialSource)
}

public func gatewayFeishuDescribeAccounts(config: FeishuConfig): JsonObject {
    let out = JsonObject()
    let defaultAccount = gatewayFeishuDefaultAccountId(config)
    out.put("channel", JsonString("feishu"))
    out.put("defaultAccountId", JsonString(defaultAccount))
    out.put("redacted", JsonBool(true))
    let rows = JsonArray([])
    for (accountId in gatewayFeishuListAccountIds(config)) {
        let resolved = gatewayFeishuResolveAccount(config, accountId)
        let row = JsonObject()
        row.put("accountId", JsonString(resolved.accountId))
        row.put("defaultAccount", JsonBool(resolved.accountId == defaultAccount))
        row.put("enabled", JsonBool(resolved.config.enabled))
        row.put("configured", JsonBool(!resolved.config.appId.trimAscii().isEmpty() && !resolved.config.appSecret.trimAscii().isEmpty()))
        row.put("credentialSource", JsonString(resolved.credentialSource))
        row.put("explicitAccount", JsonBool(resolved.explicitAccount))
        row.put("receiveMode", JsonString(resolved.config.receiveMode))
        row.put("domain", JsonString(resolved.config.domain))
        row.put("appId", JsonString(gatewayFeishuRedactedValue(resolved.config.appId)))
        row.put("appSecret", JsonString(if (resolved.config.appSecret.trimAscii().isEmpty()) { "" } else { "[redacted]" }))
        row.put("hasAppId", JsonBool(!resolved.config.appId.trimAscii().isEmpty()))
        row.put("hasAppSecret", JsonBool(!resolved.config.appSecret.trimAscii().isEmpty()))
        row.put("threadSession", JsonBool(resolved.config.threadSession))
        row.put("groupPolicy", JsonString(resolved.config.groupPolicy))
        row.put("requireMention", JsonBool(resolved.config.requireMention))
        row.put("mediaDownloadEnabled", JsonBool(resolved.config.media.downloadEnabled))
        rows.add(row)
    }
    out.put("accounts", rows)
    out.put("count", JsonInt(rows.size()))
    out
}

public func gatewayFeishuRedactedValue(value: String): String {
    let trimmed = value.trimAscii()
    if (trimmed.isEmpty()) {
        return ""
    }
    if (trimmed.size <= 6) {
        return "[redacted]"
    }
    trimmed[0..3] + "***" + trimmed[trimmed.size - 3..]
}

private func gatewayFeishuAccountOverride(config: FeishuConfig, accountId: String): Option<JsonObject> {
    match (config.accounts) {
        case Some(accounts) =>
            match (accounts.get(gatewayFeishuNormalizeAccountId(accountId))) {
                case Some(v) => try { Some(v.asObject()) } catch (_: Exception) { None<JsonObject> }
                case None => None<JsonObject>
            }
        case None => None<JsonObject>
    }
}

private func gatewayFeishuHasString(obj: JsonObject, keys: Array<String>): Bool {
    !gatewayFeishuString(obj, keys, "").isEmpty()
}

private func gatewayFeishuString(obj: JsonObject, keys: Array<String>, fallback: String): String {
    for (key in keys) {
        match (obj.get(key)) {
            case Some(v) =>
                try {
                    return v.asString().getValue().trimAscii()
                } catch (_: Exception) {
                    try {
                        return v.asInt().getValue().toString()
                    } catch (_inner: Exception) {
                        ()
                    }
                }
            case None => ()
        }
    }
    fallback.trimAscii()
}

private func gatewayFeishuBool(obj: JsonObject, key: String, fallback: Bool): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_: Exception) {
                try {
                    let raw = v.asString().getValue().trimAscii().toAsciiLower()
                    raw == "true" || raw == "1" || raw == "yes" || raw == "on"
                } catch (_inner: Exception) { fallback }
            }
        case None => fallback
    }
}

private func gatewayFeishuInt(obj: JsonObject, keys: Array<String>, fallback: Int64): Int64 {
    for (key in keys) {
        match (obj.get(key)) {
            case Some(v) =>
                try { return v.asInt().getValue() } catch (_: Exception) {
                    try { return Int64.parse(v.asString().getValue().trimAscii()) } catch (_inner: Exception) { () }
                }
            case None => ()
        }
    }
    fallback
}

private func gatewayFeishuUInt16(obj: JsonObject, keys: Array<String>, fallback: UInt16): UInt16 {
    let parsed = gatewayFeishuInt(obj, keys, Int64(fallback))
    if (parsed <= 0 || parsed > 65535) {
        return fallback
    }
    UInt16(parsed)
}

private func gatewayFeishuObjectOption(obj: JsonObject, key: String, fallback: Option<JsonObject>): Option<JsonObject> {
    match (obj.get(key)) {
        case Some(v) => try { Some(v.asObject()) } catch (_: Exception) { fallback }
        case None => fallback
    }
}

private func gatewayFeishuStringArray(obj: JsonObject, key: String, fallback: Array<String>): Array<String> {
    match (obj.get(key)) {
        case Some(v) =>
            try {
                let arr = v.asArray()
                let out = ArrayList<String>()
                for (i in 0..arr.size()) {
                    try {
                        let item = arr[i].asString().getValue().trimAscii()
                        if (!item.isEmpty()) {
                            out.add(item)
                        }
                    } catch (_: Exception) {
                        ()
                    }
                }
                return out.toArray()
            } catch (_: Exception) {
                return fallback
            }
        case None => fallback
    }
}

private func gatewayFeishuMedia(obj: JsonObject, fallback: FeishuMediaConfig): FeishuMediaConfig {
    let media = match (obj.get("media")) {
        case Some(v) => try { v.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
    FeishuMediaConfig(
        downloadEnabled: gatewayFeishuBool(media, "downloadEnabled", fallback.downloadEnabled),
        mediaMaxBytes: gatewayFeishuInt(media, ["mediaMaxBytes", "media_max_bytes"], fallback.mediaMaxBytes),
        allowedMimes: gatewayFeishuStringArray(media, "allowedMimes", fallback.allowedMimes),
        downloadRoot: gatewayFeishuString(media, ["downloadRoot", "download_root"], fallback.downloadRoot)
    )
}

private func gatewayFeishuReceiveMode(raw: String): String {
    if (raw.trimAscii().toAsciiLower() == "webhook") { "webhook" } else { "long_connect" }
}

private func gatewayFeishuGroupSessionScope(raw: String): String {
    let normalized = raw.trimAscii().toAsciiLower()
    if (normalized == "group_sender" || normalized == "group_topic" || normalized == "group_topic_sender") {
        return normalized
    }
    "group"
}

private func gatewayFeishuGroupPolicy(raw: String): String {
    match (raw.trimAscii().toAsciiLower()) {
        case "open" => "open"
        case "disabled" => "disabled"
        case _ => "allowlist"
    }
}

private func gatewayFeishuReplyInThread(raw: String): String {
    if (raw.trimAscii().toAsciiLower() == "enabled") { "enabled" } else { "disabled" }
}
