package metis.gateway.core

import metis.core.config.GatewayUserSettings

import stdx.encoding.json.{JsonBool, JsonObject, JsonString}

private var gatewayFeishuNativeAuthRunnerOverride: Option<(String, GatewayUserSettings) -> JsonObject> =
    None<(String, GatewayUserSettings) -> JsonObject>

public func setGatewayFeishuNativeAuthRunnerForTest(runner: Option<(String, GatewayUserSettings) -> JsonObject>): Unit {
    gatewayFeishuNativeAuthRunnerOverride = runner
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
    for (key in ["status", "verificationUri", "userCode", "expiresInSeconds", "message", "error"]) {
        match (raw.get(key)) {
            case Some(v) => out.put(key, v)
            case None => ()
        }
    }
    out.put("redacted", JsonBool(true))
    out
}
