package metis.gateway.channels.qq

import metis.gateway.model.{ChannelPolicyConfig, QQConfig}

import std.collection.{ArrayList, HashSet}
import std.convert.Parsable
import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject, JsonString, JsonValue}

public class QqResolvedAccount {
    public let accountId: String
    public let config: QQConfig
    public let explicitAccount: Bool
    public let missingAccount: Bool
    public let missingDiagnostic: String
    public let credentialSource: String
    public let appIdCredentialSource: String
    public let appSecretCredentialSource: String

    public init(
        accountId: String,
        config: QQConfig,
        explicitAccount!: Bool = false,
        missingAccount!: Bool = false,
        missingDiagnostic!: String = "",
        credentialSource!: String = "top-level",
        appIdCredentialSource!: String = "top-level",
        appSecretCredentialSource!: String = "top-level"
    ) {
        this.accountId = gatewayQqNormalizeAccountId(accountId)
        this.config = config
        this.explicitAccount = explicitAccount
        this.missingAccount = missingAccount
        this.missingDiagnostic = missingDiagnostic.trimAscii()
        this.credentialSource = credentialSource.trimAscii()
        this.appIdCredentialSource = appIdCredentialSource.trimAscii()
        this.appSecretCredentialSource = appSecretCredentialSource.trimAscii()
    }
}

public func gatewayQqNormalizeAccountId(raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return "default"
    }
    let lower = trimmed.toAsciiLower()
    if (lower.startsWith("qq:")) {
        let suffix = trimmed["qq:".size..].trimAscii()
        return if (suffix.isEmpty()) { "default" } else { suffix }
    }
    trimmed
}

public func gatewayQqDefaultAccountId(config: QQConfig): String {
    gatewayQqNormalizeAccountId(config.defaultAccount)
}

public func gatewayQqListAccountIds(config: QQConfig): Array<String> {
    let out = ArrayList<String>()
    let seen = HashSet<String>()
    let defaultAccount = gatewayQqDefaultAccountId(config)
    out.add(defaultAccount)
    seen.add(defaultAccount)
    match (config.accounts) {
        case Some(accounts) =>
            for (raw in accounts.getFields().keys()) {
                let id = gatewayQqNormalizeAccountId(raw)
                if (!seen.contains(id)) {
                    out.add(id)
                    seen.add(id)
                }
            }
        case None => ()
    }
    out.toArray()
}

public func gatewayQqResolveAccount(config: QQConfig, accountId: String): QqResolvedAccount {
    let normalized = if (accountId.trimAscii().isEmpty()) {
        gatewayQqDefaultAccountId(config)
    } else {
        gatewayQqNormalizeAccountId(accountId)
    }
    let defaultAccount = gatewayQqDefaultAccountId(config)
    let accountConfig = gatewayQqAccountOverride(config, normalized)
    let explicitAccount = accountConfig.isSome()
    let missingAccount = !explicitAccount && normalized != defaultAccount && gatewayQqHasAccounts(config)
    let overrideObj = accountConfig ?? JsonObject()
    let appIdSource = if (missingAccount) {
        "missing-account"
    } else {
        gatewayQqCredentialFieldSource(
            gatewayQqHasString(overrideObj, ["appId", "app_id"]),
            !config.appId.trimAscii().isEmpty()
        )
    }
    let appSecretSource = if (missingAccount) {
        "missing-account"
    } else {
        gatewayQqCredentialFieldSource(
            gatewayQqHasString(overrideObj, ["appSecret", "app_secret"]),
            !config.appSecret.trimAscii().isEmpty()
        )
    }
    let credentialSource = if (missingAccount) {
        "missing-account"
    } else {
        gatewayQqCredentialSourceSummary(appIdSource, appSecretSource)
    }
    let merged = QQConfig(
        accountId: normalized,
        defaultAccount: defaultAccount,
        enabled: gatewayQqBoolKeys(overrideObj, ["enabled"], config.enabled),
        streaming: gatewayQqString(overrideObj, ["streaming"], config.streaming),
        blockStreaming: gatewayQqBoolKeys(overrideObj, ["blockStreaming", "block_streaming"], config.blockStreaming),
        mode: gatewayQqString(overrideObj, ["mode"], config.mode),
        webhookHost: gatewayQqString(overrideObj, ["webhookHost", "webhook_host"], config.webhookHost),
        webhookPort: gatewayQqUInt16(overrideObj, ["webhookPort", "webhook_port"], config.webhookPort),
        webhookPath: gatewayQqString(overrideObj, ["webhookPath", "webhook_path"], config.webhookPath),
        accessToken: gatewayQqString(overrideObj, ["accessToken", "access_token"], config.accessToken),
        requireAuthorizationHeader: gatewayQqBoolKeys(overrideObj, ["requireAuthorizationHeader", "require_authorization_header"], config.requireAuthorizationHeader),
        onebotApiBaseUrl: gatewayQqString(overrideObj, ["onebotApiBaseUrl", "onebot_api_base_url"], config.onebotApiBaseUrl),
        sendApiMode: gatewayQqString(overrideObj, ["sendApiMode", "send_api_mode"], config.sendApiMode),
        botQQ: gatewayQqString(overrideObj, ["botQQ", "bot_qq"], config.botQQ),
        dedupWindowSize: gatewayQqInt(overrideObj, ["dedupWindowSize", "dedup_window_size"], config.dedupWindowSize),
        appId: if (missingAccount) { "" } else { gatewayQqString(overrideObj, ["appId", "app_id"], config.appId) },
        appSecret: if (missingAccount) { "" } else { gatewayQqString(overrideObj, ["appSecret", "app_secret"], config.appSecret) },
        accounts: config.accounts,
        officialBotToken: gatewayQqString(overrideObj, ["officialBotToken", "official_bot_token"], config.officialBotToken),
        officialTokenUrl: gatewayQqString(overrideObj, ["officialTokenUrl", "official_token_url"], config.officialTokenUrl),
        officialGatewayUrl: gatewayQqString(overrideObj, ["officialGatewayUrl", "official_gateway_url"], config.officialGatewayUrl),
        officialWebsocketUrl: gatewayQqString(overrideObj, ["officialWebsocketUrl", "official_websocket_url"], config.officialWebsocketUrl),
        officialAuthScheme: gatewayQqString(overrideObj, ["officialAuthScheme", "official_auth_scheme"], config.officialAuthScheme),
        officialIntents: gatewayQqInt(overrideObj, ["officialIntents", "official_intents"], config.officialIntents),
        officialSendPrivateUrlTemplate: gatewayQqString(overrideObj, ["officialSendPrivateUrlTemplate", "official_send_private_url_template"], config.officialSendPrivateUrlTemplate),
        officialSendGroupUrlTemplate: gatewayQqString(overrideObj, ["officialSendGroupUrlTemplate", "official_send_group_url_template"], config.officialSendGroupUrlTemplate),
        policy: ChannelPolicyConfig()
    )
    QqResolvedAccount(
        normalized,
        merged,
        explicitAccount: explicitAccount,
        missingAccount: missingAccount,
        missingDiagnostic: if (missingAccount) { "unknown QQ accountId \"${normalized}\"" } else { "" },
        credentialSource: credentialSource,
        appIdCredentialSource: appIdSource,
        appSecretCredentialSource: appSecretSource
    )
}

public func gatewayQqDescribeAccounts(config: QQConfig, runtime!: JsonObject = JsonObject()): JsonObject {
    let out = JsonObject()
    let defaultAccount = gatewayQqDefaultAccountId(config)
    out.put("channel", JsonString("qq"))
    out.put("defaultAccountId", JsonString(defaultAccount))
    out.put("redacted", JsonBool(true))
    let rows = JsonArray([])
    let accountIds = gatewayQqListAccountIds(config)
    out.put("routeDiagnostics", gatewayQqRouteDiagnostics(defaultAccount, accountIds.size))
    for (accountId in accountIds) {
        let resolved = gatewayQqResolveAccount(config, accountId)
        let runtimeRow = gatewayQqRuntimeAccount(runtime, resolved.accountId)
        let configured = !resolved.config.appId.trimAscii().isEmpty() && !resolved.config.appSecret.trimAscii().isEmpty()
        let running = gatewayQqRuntimeBool(runtimeRow, "running", false)
        let lastError = gatewayQqRedactSecretText(gatewayQqRuntimeString(runtimeRow, "lastError", resolved.missingDiagnostic))
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
        row.put("missingAccount", JsonBool(resolved.missingAccount))
        row.put("mode", JsonString(resolved.config.mode))
        row.put("appId", JsonString(gatewayQqRedactedValue(resolved.config.appId)))
        row.put("appSecret", JsonString(if (resolved.config.appSecret.trimAscii().isEmpty()) { "" } else { "[redacted]" }))
        row.put("hasAppId", JsonBool(!resolved.config.appId.trimAscii().isEmpty()))
        row.put("hasAppSecret", JsonBool(!resolved.config.appSecret.trimAscii().isEmpty()))
        row.put("routeDiagnostic", gatewayQqAccountRouteDiagnostic(resolved, defaultAccount, configured))
        row.put("liveReadiness", gatewayQqAccountLiveReadiness(resolved, configured, running, lastError))
        rows.add(row)
    }
    out.put("accounts", rows)
    out.put("count", JsonInt(rows.size()))
    out
}

public func gatewayQqRedactedValue(value: String): String {
    let trimmed = value.trimAscii()
    if (trimmed.isEmpty()) {
        return ""
    }
    if (trimmed.size <= 6) {
        return "[redacted]"
    }
    trimmed[0..3] + "***" + trimmed[trimmed.size - 3..]
}

public func gatewayQqRedactSecretText(raw: String): String {
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

private func gatewayQqRouteDiagnostics(defaultAccount: String, accountCount: Int64): JsonObject {
    let out = JsonObject()
    out.put("status", JsonString(if (accountCount > 1) { "multi_account_ready" } else { "single_account_ready" }))
    out.put("channel", JsonString("qq"))
    out.put("defaultAccountId", JsonString(defaultAccount))
    out.put("bindingMatchDimensions", JsonArray([
        JsonString("channel"),
        JsonString("accountId"),
        JsonString("peer"),
        JsonString("team"),
        JsonString("roles")
    ]))
    out.put("redacted", JsonBool(true))
    out
}

private func gatewayQqBindingStatus(enabled: Bool, configured: Bool, missingAccount: Bool): String {
    if (missingAccount) {
        return "unknown_account"
    }
    if (!enabled) {
        return "disabled"
    }
    if (!configured) {
        return "missing_credential"
    }
    "ready_for_binding"
}

private func gatewayQqAccountRouteDiagnostic(resolved: QqResolvedAccount, defaultAccount: String, configured: Bool): JsonObject {
    let route = JsonObject()
    route.put("channel", JsonString("qq"))
    route.put("accountId", JsonString(resolved.accountId))
    route.put("defaultAccountId", JsonString(defaultAccount))
    route.put("bindingMatchAccountId", JsonString(resolved.accountId))
    route.put("bindingStatus", JsonString(gatewayQqBindingStatus(resolved.config.enabled, configured, resolved.missingAccount)))
    route.put("mode", JsonString(resolved.config.mode))
    route.put("redacted", JsonBool(true))
    route
}

private func gatewayQqAccountLiveReadiness(
    resolved: QqResolvedAccount,
    configured: Bool,
    running: Bool,
    lastError: String
): JsonObject {
    let out = JsonObject()
    let state = if (resolved.missingAccount) {
        "unknown_account"
    } else if (!resolved.config.enabled) {
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
        case "unknown_account" => "configure_qq_account_or_use_default"
        case "disabled" => "enable_account_or_remove_binding"
        case "missing_credential" => "configure_qq_app_credentials"
        case "running" => "run_live_route_smoke"
        case "error" => "inspect_redacted_runtime_error"
        case _ => "start_gateway_or_run_live_route_smoke"
    }
    out.put("state", JsonString(state))
    out.put("nextStep", JsonString(nextStep))
    out.put("externalResourceRequired", JsonBool(state != "running"))
    out.put("redacted", JsonBool(true))
    out
}

private func gatewayQqRuntimeAccount(runtime: JsonObject, accountId: String): JsonObject {
    let accounts = match (runtime.get("accounts")) {
        case Some(v) => try { v.asArray() } catch (_: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    for (i in 0..accounts.size()) {
        let row = try { accounts[i].asObject() } catch (_: Exception) { JsonObject() }
        if (gatewayQqRuntimeString(row, "accountId", "") == accountId) {
            return row
        }
    }
    JsonObject()
}

private func gatewayQqRuntimeString(obj: JsonObject, key: String, fallback: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_: Exception) { fallback }
        case None => fallback
    }
}

private func gatewayQqRuntimeBool(obj: JsonObject, key: String, fallback: Bool): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_: Exception) { fallback }
        case None => fallback
    }
}

private func gatewayQqAccountOverride(config: QQConfig, accountId: String): Option<JsonObject> {
    match (config.accounts) {
        case Some(accounts) =>
            let normalized = gatewayQqNormalizeAccountId(accountId)
            let raw = match (accounts.get(normalized)) {
                case Some(v) => Some(v)
                case None => accounts.get("qq:${normalized}")
            }
            match (raw) {
                case Some(v) => try { Some(v.asObject()) } catch (_: Exception) { None<JsonObject> }
                case None => None<JsonObject>
            }
        case None => None<JsonObject>
    }
}

private func gatewayQqHasAccounts(config: QQConfig): Bool {
    match (config.accounts) {
        case Some(accounts) => accounts.size() > 0
        case None => false
    }
}

private func gatewayQqHasString(obj: JsonObject, keys: Array<String>): Bool {
    !gatewayQqString(obj, keys, "").isEmpty()
}

private func gatewayQqCredentialFieldSource(accountHasValue: Bool, topLevelHasValue: Bool): String {
    if (accountHasValue) {
        return "account"
    }
    if (topLevelHasValue) {
        return "top-level"
    }
    "missing"
}

private func gatewayQqCredentialSourceSummary(appIdSource: String, appSecretSource: String): String {
    if (appIdSource == "account" && appSecretSource == "account") {
        return "account"
    }
    if (appIdSource == "missing" || appSecretSource == "missing") {
        return "missing"
    }
    if (appIdSource == appSecretSource) {
        return appIdSource
    }
    "mixed"
}

private func gatewayQqString(obj: JsonObject, keys: Array<String>, fallback: String): String {
    for (key in keys) {
        match (obj.get(key)) {
            case Some(v) =>
                try {
                    let s = v.asString().getValue().trimAscii()
                    if (!s.isEmpty()) {
                        return s
                    }
                } catch (_: Exception) {
                    ()
                }
            case None => ()
        }
    }
    fallback
}

private func gatewayQqBoolKeys(obj: JsonObject, keys: Array<String>, fallback: Bool): Bool {
    for (key in keys) {
        match (obj.get(key)) {
            case Some(v) =>
                try { return v.asBool().getValue() } catch (_: Exception) { () }
                try {
                    let s = v.asString().getValue().trimAscii().toAsciiLower()
                    if (s == "true" || s == "1" || s == "yes" || s == "enabled") {
                        return true
                    }
                    if (s == "false" || s == "0" || s == "no" || s == "disabled") {
                        return false
                    }
                } catch (_: Exception) {
                    ()
                }
            case None => ()
        }
    }
    fallback
}

private func gatewayQqInt(obj: JsonObject, keys: Array<String>, fallback: Int64): Int64 {
    for (key in keys) {
        match (obj.get(key)) {
            case Some(v) =>
                try { return Int64.parse(v.toJsonString().trimAscii().replace("\"", "")) } catch (_: Exception) { () }
            case None => ()
        }
    }
    fallback
}

private func gatewayQqUInt16(obj: JsonObject, keys: Array<String>, fallback: UInt16): UInt16 {
    let parsed = gatewayQqInt(obj, keys, Int64(fallback))
    if (parsed <= 0 || parsed > 65535) {
        return fallback
    }
    UInt16(parsed)
}
