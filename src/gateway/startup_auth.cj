package metis.gateway

import metis.core.config.GatewayUserSettings
import metis.gateway.logging.{MetisLogEvent, metisCreateSubsystemLogger}

import std.random.Random

private var gatewayRuntimeAuthTokenOverride: String = ""
private var gatewayRuntimeAuthPasswordOverride: String = ""

private func gatewayStartupRandomHex(count: Int64): String {
    let rand = Random()
    let chars = "0123456789abcdef".toRuneArray()
    let result = StringBuilder()
    for (_ in 0..count) {
        let raw = rand.nextInt64()
        let idx = Int64((raw % chars.size + chars.size) % chars.size)
        result.append(chars[idx])
    }
    result.toString()
}

public func gatewayRuntimeEffectiveAuthToken(user: GatewayUserSettings): String {
    gatewayRuntimeEffectiveAuthTokenString(user.auth.token)
}

public func gatewayRuntimeEffectiveAuthPassword(user: GatewayUserSettings): String {
    gatewayRuntimeEffectiveAuthPasswordString(user.auth.password)
}

public func gatewayRuntimeEffectiveAuthTokenString(configured: String): String {
    let runtime = gatewayRuntimeAuthTokenOverride.trimAscii()
    if (!runtime.isEmpty()) {
        return runtime
    }
    configured.trimAscii()
}

public func gatewayRuntimeEffectiveAuthPasswordString(configured: String): String {
    let runtime = gatewayRuntimeAuthPasswordOverride.trimAscii()
    if (!runtime.isEmpty()) {
        return runtime
    }
    configured.trimAscii()
}

public func gatewayPrepareStartupAuth(user: GatewayUserSettings): (GatewayUserSettings, Bool, Bool) {
    gatewayRuntimeAuthTokenOverride = ""
    gatewayRuntimeAuthPasswordOverride = ""

    let mode = user.auth.mode.trimAscii().toAsciiLower()
    let configuredToken = user.auth.token.trimAscii()
    if (mode != "token" || !configuredToken.isEmpty()) {
        return (user, false, false)
    }

    let generatedToken = gatewayStartupRandomHex(48)
    var updated = user
    updated.auth.mode = "token"
    updated.auth.token = generatedToken
    gatewayRuntimeAuthTokenOverride = generatedToken

    metisCreateSubsystemLogger("gateway/auth").info(
        MetisLogEvent.gatewayStarting,
        "generated runtime-only gateway auth token; config was not modified"
    )
    (updated, true, false)
}
