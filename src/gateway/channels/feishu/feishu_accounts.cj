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
    public let appIdCredentialSource: String
    public let appSecretCredentialSource: String

    public init(
        accountId: String,
        config: FeishuConfig,
        explicitAccount!: Bool = false,
        credentialSource!: String = "top-level",
        appIdCredentialSource!: String = "top-level",
        appSecretCredentialSource!: String = "top-level"
    ) {
        this.accountId = gatewayFeishuNormalizeAccountId(accountId)
        this.config = config
        this.explicitAccount = explicitAccount
        this.credentialSource = credentialSource.trimAscii()
        this.appIdCredentialSource = appIdCredentialSource.trimAscii()
        this.appSecretCredentialSource = appSecretCredentialSource.trimAscii()
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
    let appIdSource = gatewayFeishuCredentialFieldSource(
        gatewayFeishuHasString(overrideObj, ["appId", "app_id"]),
        !config.appId.trimAscii().isEmpty()
    )
    let appSecretSource = gatewayFeishuCredentialFieldSource(
        gatewayFeishuHasString(overrideObj, ["appSecret", "app_secret"]),
        !config.appSecret.trimAscii().isEmpty()
    )
    let credentialSource = gatewayFeishuCredentialSourceSummary(appIdSource, appSecretSource)
    let threadSession = gatewayFeishuBoolKeys(overrideObj, ["threadSession", "thread_session"], config.threadSession)
    let groupPolicy = gatewayFeishuGroupPolicy(gatewayFeishuString(overrideObj, ["groupPolicy", "group_policy"], config.groupPolicy))
    let groupAllowFrom = gatewayFeishuStringArray(overrideObj, ["groupAllowFrom", "group_allow_from"], config.groupAllowFrom)
    let requireMention = gatewayFeishuBoolKeys(overrideObj, ["requireMention", "require_mention"], config.requireMention)
    let allowBots = gatewayFeishuBoolKeys(overrideObj, ["allowBots", "allow_bots"], config.allowBots)
    let merged = FeishuConfig(
        accountId: normalized,
        defaultAccount: gatewayFeishuDefaultAccountId(config),
        enabled: gatewayFeishuBoolKeys(overrideObj, ["enabled"], config.enabled),
        streaming: gatewayFeishuString(overrideObj, ["streaming"], config.streaming),
        blockStreaming: gatewayFeishuBoolKeys(overrideObj, ["blockStreaming", "block_streaming"], config.blockStreaming),
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
        threadSession: threadSession,
        groups: gatewayFeishuMergedObjectOption(overrideObj, "groups", config.groups),
        groupPolicy: groupPolicy,
        groupAllowFrom: groupAllowFrom,
        requireMention: requireMention,
        allowBots: allowBots,
        replyInThread: gatewayFeishuReplyInThread(gatewayFeishuString(overrideObj, ["replyInThread", "reply_in_thread"], config.replyInThread)),
        requireSignatureHeaders: gatewayFeishuBoolKeys(overrideObj, ["requireSignatureHeaders", "require_signature_headers"], config.requireSignatureHeaders),
        requestMaxSkewSeconds: gatewayFeishuInt(overrideObj, ["requestMaxSkewSeconds", "request_max_skew_seconds"], config.requestMaxSkewSeconds),
        media: gatewayFeishuMedia(overrideObj, config.media),
        policy: ChannelPolicyConfig(
            allowFrom: [],
            requireMentionInGroup: requireMention,
            enableDirect: true,
            enableGroup: groupPolicy != "disabled"
        )
    )
    FeishuResolvedAccount(
        normalized,
        merged,
        explicitAccount: explicitAccount,
        credentialSource: credentialSource,
        appIdCredentialSource: appIdSource,
        appSecretCredentialSource: appSecretSource
    )
}

public func gatewayFeishuDescribeAccounts(config: FeishuConfig, runtime!: JsonObject = JsonObject()): JsonObject {
    let out = JsonObject()
    let defaultAccount = gatewayFeishuDefaultAccountId(config)
    let diagnostics = gatewayFeishuUnsupportedFieldDiagnostics(config)
    out.put("channel", JsonString("feishu"))
    out.put("defaultAccountId", JsonString(defaultAccount))
    out.put("redacted", JsonBool(true))
    out.put("unsupportedFields", diagnostics.get("unsupportedFields") ?? JsonArray([]))
    out.put("ignoredFields", diagnostics.get("ignoredFields") ?? JsonArray([]))
    out.put("unsupportedFieldCount", diagnostics.get("unsupportedFieldCount") ?? JsonInt(0))
    out.put("ignoredFieldCount", diagnostics.get("ignoredFieldCount") ?? JsonInt(0))
    let rows = JsonArray([])
    let accountIds = gatewayFeishuListAccountIds(config)
    out.put("routeDiagnostics", gatewayFeishuRouteDiagnostics(defaultAccount, accountIds.size))
    for (accountId in accountIds) {
        let resolved = gatewayFeishuResolveAccount(config, accountId)
        let runtimeRow = gatewayFeishuRuntimeAccount(runtime, resolved.accountId)
        let configured = !resolved.config.appId.trimAscii().isEmpty() && !resolved.config.appSecret.trimAscii().isEmpty()
        let running = gatewayFeishuRuntimeBool(runtimeRow, "running", false)
        let lastError = gatewayFeishuRedactSecretText(gatewayFeishuRuntimeString(runtimeRow, "lastError", ""))
        let row = JsonObject()
        row.put("accountId", JsonString(resolved.accountId))
        row.put("defaultAccount", JsonBool(resolved.accountId == defaultAccount))
        row.put("enabled", JsonBool(resolved.config.enabled))
        row.put("configured", JsonBool(configured))
        row.put("running", JsonBool(running))
        row.put("lastError", JsonString(lastError))
        row.put("credentialSource", JsonString(resolved.credentialSource))
        let credentialSources = JsonObject()
        credentialSources.put("summary", JsonString(resolved.credentialSource))
        credentialSources.put("appId", JsonString(resolved.appIdCredentialSource))
        credentialSources.put("appSecret", JsonString(resolved.appSecretCredentialSource))
        credentialSources.put("redacted", JsonBool(true))
        row.put("credentialSources", credentialSources)
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
        row.put("routeDiagnostic", gatewayFeishuAccountRouteDiagnostic(resolved, defaultAccount, configured))
        row.put("liveReadiness", gatewayFeishuAccountLiveReadiness(resolved, configured, running, lastError))
        rows.add(row)
    }
    out.put("accounts", rows)
    out.put("count", JsonInt(rows.size()))
    out
}

private func gatewayFeishuRouteDiagnostics(defaultAccount: String, accountCount: Int64): JsonObject {
    let out = JsonObject()
    out.put("status", JsonString(if (accountCount > 1) { "multi_account_ready" } else { "single_account_ready" }))
    out.put("channel", JsonString("feishu"))
    out.put("defaultAccountId", JsonString(defaultAccount))
    out.put("bindingMatchDimensions", JsonArray([
        JsonString("channel"),
        JsonString("accountId"),
        JsonString("peer"),
        JsonString("team"),
        JsonString("roles")
    ]))
    out.put("manualAcceptance", JsonArray([
        JsonString("M15"),
        JsonString("M16"),
        JsonString("M17"),
        JsonString("M22")
    ]))
    out.put("redacted", JsonBool(true))
    out
}

private func gatewayFeishuBindingStatus(enabled: Bool, configured: Bool): String {
    if (!enabled) {
        return "disabled"
    }
    if (!configured) {
        return "missing_credential"
    }
    "ready_for_binding"
}

private func gatewayFeishuAccountRouteDiagnostic(
    resolved: FeishuResolvedAccount,
    defaultAccount: String,
    configured: Bool
): JsonObject {
    let route = JsonObject()
    route.put("channel", JsonString("feishu"))
    route.put("accountId", JsonString(resolved.accountId))
    route.put("defaultAccountId", JsonString(defaultAccount))
    route.put("bindingMatchAccountId", JsonString(resolved.accountId))
    route.put("bindingStatus", JsonString(gatewayFeishuBindingStatus(resolved.config.enabled, configured)))
    route.put("groupPolicy", JsonString(resolved.config.groupPolicy))
    route.put("requireMention", JsonBool(resolved.config.requireMention))
    route.put("threadSession", JsonBool(resolved.config.threadSession))
    route.put("groupSessionScope", JsonString(resolved.config.groupSessionScope))
    route.put("replyInThread", JsonString(resolved.config.replyInThread))
    route.put("sessionKeyBoundary", JsonString(if (resolved.config.threadSession) { "account_peer_thread" } else { "account_peer" }))
    route.put("redacted", JsonBool(true))
    route
}

private func gatewayFeishuAccountLiveReadiness(
    resolved: FeishuResolvedAccount,
    configured: Bool,
    running: Bool,
    lastError: String
): JsonObject {
    let out = JsonObject()
    let state = if (!resolved.config.enabled) {
        "disabled"
    } else if (!configured) {
        "missing_credential"
    } else if (running) {
        "running"
    } else if (!lastError.trimAscii().isEmpty()) {
        "error"
    } else {
        "configured"
    }
    let nextStep = match (state) {
        case "disabled" => "enable_account_or_remove_binding"
        case "missing_credential" => "configure_feishu_app_credentials"
        case "running" => "run_live_route_smoke"
        case "error" => "inspect_redacted_runtime_error"
        case _ => "start_gateway_or_run_live_route_smoke"
    }
    out.put("state", JsonString(state))
    out.put("nextStep", JsonString(nextStep))
    out.put("externalResourceRequired", JsonBool(state != "running"))
    out.put("manualAcceptance", JsonArray([
        JsonString("M15"),
        JsonString("M16"),
        JsonString("M17")
    ]))
    out.put("redacted", JsonBool(true))
    out
}

private func gatewayFeishuRuntimeAccount(runtime: JsonObject, accountId: String): JsonObject {
    let accounts = match (runtime.get("accounts")) {
        case Some(v) => try { v.asArray() } catch (_: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    for (i in 0..accounts.size()) {
        let row = try { accounts[i].asObject() } catch (_: Exception) { JsonObject() }
        if (gatewayFeishuRuntimeString(row, "accountId", "") == accountId) {
            return row
        }
    }
    JsonObject()
}

private func gatewayFeishuRuntimeString(obj: JsonObject, key: String, fallback: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_: Exception) { fallback }
        case None => fallback
    }
}

private func gatewayFeishuRuntimeBool(obj: JsonObject, key: String, fallback: Bool): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_: Exception) { fallback }
        case None => fallback
    }
}

private func gatewayFeishuRedactSecretText(raw: String): String {
    let text = raw.trimAscii()
    if (text.isEmpty()) {
        return ""
    }
    let lower = text.toAsciiLower()
    if (
        lower.contains("authorization") ||
        lower.contains("bearer ") ||
        lower.contains("secret") ||
        lower.contains("token") ||
        lower.contains("password")
    ) {
        return "[redacted]"
    }
    text
}

public func gatewayFeishuUnsupportedFieldDiagnostics(config: FeishuConfig): JsonObject {
    let unsupported = JsonArray([])
    let ignored = JsonArray([])
    match (config.accounts) {
        case Some(accounts) =>
            for (rawAccountId in accounts.getFields().keys()) {
                let accountId = gatewayFeishuNormalizeAccountId(rawAccountId)
                let accountObj = try { accounts.getFields()[rawAccountId].asObject() } catch (_: Exception) { JsonObject() }
                for (key in accountObj.getFields().keys()) {
                    if (key == "groups") {
                        gatewayFeishuCollectUnsupportedGroupFields(
                            accountObj,
                            "accounts.${accountId}.groups",
                            unsupported,
                            ignored
                        )
                    } else if (!gatewayFeishuSupportedAccountOverrideField(key)) {
                        gatewayFeishuAddUnsupportedIgnoredField(
                            unsupported,
                            ignored,
                            "accounts.${accountId}.${key}",
                            "account",
                            "unsupported Feishu account override field is ignored by the native runtime"
                        )
                    }
                }
            }
        case None => ()
    }
    match (config.groups) {
        case Some(groups) =>
            let wrapper = JsonObject()
            wrapper.put("groups", groups)
            gatewayFeishuCollectUnsupportedGroupFields(wrapper, "groups", unsupported, ignored)
        case None => ()
    }
    let out = JsonObject()
    out.put("unsupportedFields", unsupported)
    out.put("ignoredFields", ignored)
    out.put("unsupportedFieldCount", JsonInt(unsupported.size()))
    out.put("ignoredFieldCount", JsonInt(ignored.size()))
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

private func gatewayFeishuStringInList(value: String, allowed: Array<String>): Bool {
    for (candidate in allowed) {
        if (value == candidate) {
            return true
        }
    }
    false
}

private func gatewayFeishuSupportedAccountOverrideField(raw: String): Bool {
    gatewayFeishuStringInList(raw.trimAscii(), [
        "enabled",
        "streaming",
        "blockStreaming",
        "appId",
        "app_id",
        "appSecret",
        "app_secret",
        "receiveMode",
        "receive_mode",
        "domain",
        "botOpenId",
        "bot_open_id",
        "webhookHost",
        "webhook_host",
        "webhookPort",
        "webhook_port",
        "webhookPath",
        "webhook_path",
        "verificationToken",
        "verification_token",
        "encryptKey",
        "encrypt_key",
        "groupSessionScope",
        "group_session_scope",
        "threadSession",
        "groups",
        "groupPolicy",
        "group_policy",
        "groupAllowFrom",
        "requireMention",
        "allowBots",
        "replyInThread",
        "reply_in_thread",
        "requireSignatureHeaders",
        "requestMaxSkewSeconds",
        "request_max_skew_seconds",
        "media"
    ])
}

private func gatewayFeishuSupportedGroupOverrideField(raw: String): Bool {
    gatewayFeishuStringInList(raw.trimAscii(), [
        "enabled",
        "allowBots",
        "requireMention",
        "allowFrom",
        "tools",
        "skills",
        "systemPrompt",
        "runtimePolicy",
        "policy"
    ])
}

private func gatewayFeishuAddUnsupportedIgnoredField(
    unsupported: JsonArray,
    ignored: JsonArray,
    path: String,
    scope: String,
    reason: String
): Unit {
    let unsupportedRow = JsonObject()
    unsupportedRow.put("path", JsonString(path))
    unsupportedRow.put("scope", JsonString(scope))
    unsupportedRow.put("status", JsonString("unsupported"))
    unsupportedRow.put("effect", JsonString("ignored"))
    unsupportedRow.put("reason", JsonString(reason))
    unsupported.add(unsupportedRow)

    let ignoredRow = JsonObject()
    ignoredRow.put("path", JsonString(path))
    ignoredRow.put("scope", JsonString(scope))
    ignoredRow.put("status", JsonString("ignored"))
    ignoredRow.put("unsupported", JsonBool(true))
    ignoredRow.put("reason", JsonString(reason))
    ignored.add(ignoredRow)
}

private func gatewayFeishuCollectUnsupportedGroupFields(
    container: JsonObject,
    pathPrefix: String,
    unsupported: JsonArray,
    ignored: JsonArray
): Unit {
    let groups = match (container.get("groups")) {
        case Some(v) => try { v.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
    for (groupId in groups.getFields().keys()) {
        let groupObj = try { groups.getFields()[groupId].asObject() } catch (_: Exception) { JsonObject() }
        for (key in groupObj.getFields().keys()) {
            if (!gatewayFeishuSupportedGroupOverrideField(key)) {
                gatewayFeishuAddUnsupportedIgnoredField(
                    unsupported,
                    ignored,
                    "${pathPrefix}.${groupId}.${key}",
                    "groupPolicy",
                    "unsupported Feishu group policy field is ignored by the native runtime"
                )
            }
        }
    }
}

private func gatewayFeishuHasString(obj: JsonObject, keys: Array<String>): Bool {
    !gatewayFeishuString(obj, keys, "").isEmpty()
}

private func gatewayFeishuCredentialFieldSource(accountHasValue: Bool, topLevelHasValue: Bool): String {
    if (accountHasValue) {
        return "account"
    }
    if (topLevelHasValue) {
        return "top-level"
    }
    "missing"
}

private func gatewayFeishuCredentialSourceSummary(appIdSource: String, appSecretSource: String): String {
    if (appIdSource == "missing" && appSecretSource == "missing") {
        return "missing"
    }
    if (appIdSource == appSecretSource) {
        return appIdSource
    }
    if (appIdSource == "missing" || appSecretSource == "missing") {
        return "partial"
    }
    "mixed"
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
    gatewayFeishuBoolKeys(obj, [key], fallback)
}

private func gatewayFeishuBoolKeys(obj: JsonObject, keys: Array<String>, fallback: Bool): Bool {
    for (key in keys) {
        match (obj.get(key)) {
            case Some(v) =>
                try { return v.asBool().getValue() } catch (_: Exception) {
                    try {
                        let raw = v.asString().getValue().trimAscii().toAsciiLower()
                        return raw == "true" || raw == "1" || raw == "yes" || raw == "on"
                    } catch (_inner: Exception) {
                        return fallback
                    }
                }
            case None => ()
        }
    }
    fallback
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

private func gatewayFeishuCloneValue(value: JsonValue): JsonValue {
    try {
        JsonValue.fromStr(value.toJsonString())
    } catch (_: Exception) {
        value
    }
}

private func gatewayFeishuCloneObject(obj: JsonObject): JsonObject {
    try {
        JsonValue.fromStr(obj.toJsonString()).asObject()
    } catch (_: Exception) {
        JsonObject()
    }
}

private func gatewayFeishuDeepMergeObject(base: JsonObject, overrideObj: JsonObject): JsonObject {
    let out = gatewayFeishuCloneObject(base)
    for (key in overrideObj.getFields().keys()) {
        match (overrideObj.get(key)) {
            case Some(overrideValue) =>
                let mergedValue = match (out.get(key)) {
                    case Some(baseValue) =>
                        try {
                            let baseObj = baseValue.asObject()
                            let overrideChild = overrideValue.asObject()
                            gatewayFeishuDeepMergeObject(baseObj, overrideChild)
                        } catch (_: Exception) {
                            gatewayFeishuCloneValue(overrideValue)
                        }
                    case None => gatewayFeishuCloneValue(overrideValue)
                }
                out.put(key, mergedValue)
            case None => ()
        }
    }
    out
}

private func gatewayFeishuMergedObjectOption(obj: JsonObject, key: String, fallback: Option<JsonObject>): Option<JsonObject> {
    match (obj.get(key)) {
        case Some(v) =>
            try {
                let overrideObj = v.asObject()
                match (fallback) {
                    case Some(base) => Some(gatewayFeishuDeepMergeObject(base, overrideObj))
                    case None => Some(gatewayFeishuCloneObject(overrideObj))
                }
            } catch (_: Exception) {
                fallback
            }
        case None => fallback
    }
}

private func gatewayFeishuStringArray(obj: JsonObject, keys: Array<String>, fallback: Array<String>): Array<String> {
    for (key in keys) {
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
            case None => ()
        }
    }
    fallback
}

private func gatewayFeishuMedia(obj: JsonObject, fallback: FeishuMediaConfig): FeishuMediaConfig {
    let media = match (obj.get("media")) {
        case Some(v) => try { v.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
    FeishuMediaConfig(
        downloadEnabled: gatewayFeishuBoolKeys(media, ["downloadEnabled", "download_enabled"], fallback.downloadEnabled),
        mediaMaxBytes: gatewayFeishuInt(media, ["mediaMaxBytes", "media_max_bytes"], fallback.mediaMaxBytes),
        allowedMimes: gatewayFeishuStringArray(media, ["allowedMimes", "allowed_mimes"], fallback.allowedMimes),
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
