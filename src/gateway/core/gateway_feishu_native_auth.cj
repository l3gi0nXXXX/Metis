package metis.gateway.core

import metis.core.config.GatewayUserSettings

import stdx.encoding.json.{JsonBool, JsonObject, JsonString, JsonValue}

private var gatewayFeishuNativeAuthRunnerOverride: Option<(String, GatewayUserSettings) -> JsonObject> =
    None<(String, GatewayUserSettings) -> JsonObject>
private var gatewayFeishuNativeAuthStatusRunnerOverride: Option<(String, GatewayUserSettings) -> JsonObject> =
    None<(String, GatewayUserSettings) -> JsonObject>
private var gatewayFeishuNativeAuthPollRunnerOverride: Option<(String, GatewayUserSettings) -> JsonObject> =
    None<(String, GatewayUserSettings) -> JsonObject>
private var gatewayFeishuNativeAuthCompleteRunnerOverride: Option<(String, GatewayUserSettings) -> JsonObject> =
    None<(String, GatewayUserSettings) -> JsonObject>
private var gatewayFeishuNativeAuthRevokeRunnerOverride: Option<(String, GatewayUserSettings) -> JsonObject> =
    None<(String, GatewayUserSettings) -> JsonObject>

public func setGatewayFeishuNativeAuthRunner(runner: Option<(String, GatewayUserSettings) -> JsonObject>): Unit {
    gatewayFeishuNativeAuthRunnerOverride = runner
}

public func setGatewayFeishuNativeAuthStatusRunner(runner: Option<(String, GatewayUserSettings) -> JsonObject>): Unit {
    gatewayFeishuNativeAuthStatusRunnerOverride = runner
}

public func setGatewayFeishuNativeAuthPollRunner(runner: Option<(String, GatewayUserSettings) -> JsonObject>): Unit {
    gatewayFeishuNativeAuthPollRunnerOverride = runner
}

public func setGatewayFeishuNativeAuthCompleteRunner(runner: Option<(String, GatewayUserSettings) -> JsonObject>): Unit {
    gatewayFeishuNativeAuthCompleteRunnerOverride = runner
}

public func setGatewayFeishuNativeAuthRevokeRunner(runner: Option<(String, GatewayUserSettings) -> JsonObject>): Unit {
    gatewayFeishuNativeAuthRevokeRunnerOverride = runner
}

public func setGatewayFeishuNativeAuthRunnerForTest(runner: Option<(String, GatewayUserSettings) -> JsonObject>): Unit {
    setGatewayFeishuNativeAuthRunner(runner)
}

public func setGatewayFeishuNativeAuthStatusRunnerForTest(runner: Option<(String, GatewayUserSettings) -> JsonObject>): Unit {
    setGatewayFeishuNativeAuthStatusRunner(runner)
}

public func setGatewayFeishuNativeAuthPollRunnerForTest(runner: Option<(String, GatewayUserSettings) -> JsonObject>): Unit {
    setGatewayFeishuNativeAuthPollRunner(runner)
}

public func setGatewayFeishuNativeAuthCompleteRunnerForTest(runner: Option<(String, GatewayUserSettings) -> JsonObject>): Unit {
    setGatewayFeishuNativeAuthCompleteRunner(runner)
}

public func setGatewayFeishuNativeAuthRevokeRunnerForTest(runner: Option<(String, GatewayUserSettings) -> JsonObject>): Unit {
    setGatewayFeishuNativeAuthRevokeRunner(runner)
}

public func gatewayFeishuNativeAuthStart(accountId: String, user: GatewayUserSettings): JsonObject {
    let normalized = gatewayFeishuNativeAccountId(accountId, user)
    match (gatewayFeishuNativeAuthRunnerOverride) {
        case Some(runner) => return gatewayFeishuNativeRedactAuthResult(runner(normalized, user), normalized)
        case None => ()
    }
    let out = JsonObject()
    out.put("status", JsonString(if (gatewayFeishuNativeHasCredentials(normalized, user)) { "not_configured" } else { "missing_app_credentials" }))
    out.put("accountId", JsonString(normalized))
    out.put("message", JsonString("Feishu OAuth device-flow client is not configured for this runtime."))
    out.put("redacted", JsonBool(true))
    out
}

public func gatewayFeishuNativeAuthStatus(accountId: String, user: GatewayUserSettings): JsonObject {
    gatewayFeishuNativeAuthAction(accountId, user, gatewayFeishuNativeAuthStatusRunnerOverride, "status")
}

public func gatewayFeishuNativeAuthPoll(accountId: String, user: GatewayUserSettings): JsonObject {
    gatewayFeishuNativeAuthAction(accountId, user, gatewayFeishuNativeAuthPollRunnerOverride, "poll")
}

public func gatewayFeishuNativeAuthComplete(accountId: String, user: GatewayUserSettings): JsonObject {
    gatewayFeishuNativeAuthAction(accountId, user, gatewayFeishuNativeAuthCompleteRunnerOverride, "complete")
}

public func gatewayFeishuNativeAuthRevoke(accountId: String, user: GatewayUserSettings): JsonObject {
    gatewayFeishuNativeAuthAction(accountId, user, gatewayFeishuNativeAuthRevokeRunnerOverride, "revoke")
}

private func gatewayFeishuNativeAuthAction(
    accountId: String,
    user: GatewayUserSettings,
    runnerOverride: Option<(String, GatewayUserSettings) -> JsonObject>,
    action: String
): JsonObject {
    let normalized = gatewayFeishuNativeAccountId(accountId, user)
    match (runnerOverride) {
        case Some(runner) => return gatewayFeishuNativeRedactAuthResult(runner(normalized, user), normalized)
        case None => ()
    }
    let out = JsonObject()
    out.put("status", JsonString(if (gatewayFeishuNativeHasCredentials(normalized, user)) { "not_configured" } else { "missing_app_credentials" }))
    out.put("accountId", JsonString(normalized))
    out.put("action", JsonString(action))
    out.put("message", JsonString("Feishu OAuth device-flow client is not configured for this runtime."))
    out.put("redacted", JsonBool(true))
    out
}

private func gatewayFeishuNativeAccountId(raw: String, user: GatewayUserSettings): String {
    let trimmed = raw.trimAscii()
    if (!trimmed.isEmpty()) {
        return trimmed
    }
    let configuredDefault = user.feishu.defaultAccount.trimAscii()
    if (configuredDefault.isEmpty()) { "default" } else { configuredDefault }
}

private func gatewayFeishuNativeHasCredentials(accountId: String, user: GatewayUserSettings): Bool {
    let account = gatewayFeishuNativeAccountConfig(accountId, user)
    let appId = gatewayFeishuNativeJsonString(account, ["appId", "app_id"], user.feishu.appId)
    let appSecret = gatewayFeishuNativeJsonString(account, ["appSecret", "app_secret"], user.feishu.appSecret)
    !appId.trimAscii().isEmpty() && !appSecret.trimAscii().isEmpty()
}

private func gatewayFeishuNativeAccountConfig(accountId: String, user: GatewayUserSettings): JsonObject {
    let normalized = gatewayFeishuNativeAccountId(accountId, user)
    match (user.feishu.accounts) {
        case Some(accounts) =>
            match (accounts.get(normalized)) {
                case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
                case None => JsonObject()
            }
        case None => JsonObject()
    }
}

private func gatewayFeishuNativeJsonString(obj: JsonObject, keys: Array<String>, fallback: String): String {
    for (key in keys) {
        match (obj.get(key)) {
            case Some(v) => try { return v.asString().getValue().trimAscii() } catch (_e: Exception) { () }
            case None => ()
        }
    }
    fallback.trimAscii()
}

private func gatewayFeishuNativeRedactAuthResult(raw: JsonObject, accountId: String): JsonObject {
    let out = JsonObject()
    out.put("accountId", JsonString(accountId))
    for (key in [
        "status",
        "verificationUri",
        "userCode",
        "expiresInSeconds",
        "expiresAtMs",
        "intervalSeconds",
        "message",
        "error",
        "tokenStatus",
        "scopeSummary",
        "authorized",
        "pending",
        "revoked",
        "hasAccessToken",
        "hasRefreshToken",
        "hasDeviceCode",
        "scopes"
    ]) {
        match (raw.get(key)) {
            case Some(v) =>
                if (key == "error") {
                    out.put(key, JsonString(gatewayFeishuNativeRedactSensitiveText(gatewayFeishuNativeJsonValueString(v))))
                } else {
                    out.put(key, v)
                }
            case None => ()
        }
    }
    out.put("redacted", JsonBool(true))
    out
}

private func gatewayFeishuNativeJsonValueString(value: JsonValue): String {
    try { value.asString().getValue() } catch (_: Exception) { value.toJsonString() }
}

private func gatewayFeishuNativeRedactSensitiveText(raw: String): String {
    let text = raw.trimAscii()
    if (text.isEmpty()) {
        return ""
    }
    let lower = text.toAsciiLower()
    if (
        lower.contains("authorization") ||
        lower.contains("bearer ") ||
        lower.contains("access_token") ||
        lower.contains("refresh_token") ||
        lower.contains("client_secret") ||
        lower.contains("appsecret") ||
        lower.contains("secret") ||
        lower.contains("token") ||
        lower.contains("password")
    ) {
        return "[redacted]"
    }
    text
}
