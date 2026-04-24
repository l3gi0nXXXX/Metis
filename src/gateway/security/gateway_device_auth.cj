package metis.gateway.security

import magic.jsonable.*

import metis.core.config.CliConfig

import std.collection.HashMap
import std.fs.{File, exists}
import std.time.DateTime
import stdx.encoding.json.{JsonObject, JsonString, JsonValue}

private let GATEWAY_DEVICE_AUTH_DEFAULT_DEVICE_ID = "metis-control-ui-local"

public func gatewayDeviceAuthPath(): String {
    CliConfig.dotDir.join("gateway-device-auth.json").toString()
}

public func gatewayDefaultControlUiDeviceId(): String {
    GATEWAY_DEVICE_AUTH_DEFAULT_DEVICE_ID
}

private func gatewayNowMsForDeviceAuth(): Int64 {
    DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000
}

private func readGatewayDeviceRegistry(): JsonObject {
    let path = CliConfig.dotDir.join("gateway-device-auth.json")
    if (!exists(path)) {
        return JsonObject()
    }
    try {
        JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject()
    } catch (_e: Exception) {
        JsonObject()
    }
}

private func writeGatewayDeviceRegistry(root: JsonObject): Unit {
    File.writeTo(CliConfig.dotDir.join("gateway-device-auth.json"), root.toJsonString().toArray())
}

private func generateGatewayDeviceToken(deviceId: String): String {
    "dev-${deviceId.trimAscii()}-${gatewayNowMsForDeviceAuth()}"
}

public func gatewayEnsureDeviceToken(deviceId: String, displayName!: String = ""): String {
    let normalized = deviceId.trimAscii()
    if (normalized.isEmpty()) {
        return ""
    }
    let root = readGatewayDeviceRegistry()
    match (root.get(normalized)) {
        case Some(v) =>
            try {
                let obj = v.asObject()
                match (obj.get("token")) {
                    case Some(tok) =>
                        let text = tok.asString().getValue().trimAscii()
                        if (!text.isEmpty()) {
                            return text
                        }
                    case None => ()
                }
            } catch (_e: Exception) {
                ()
            }
        case None => ()
    }
    let token = generateGatewayDeviceToken(normalized)
    let row = JsonObject()
    row.put("token", JsonString(token))
    row.put("displayName", JsonString(displayName.trimAscii()))
    row.put("issuedAtMs", gatewayNowMsForDeviceAuth().toJsonValue())
    root.put(normalized, row)
    writeGatewayDeviceRegistry(root)
    token
}

public func gatewayDefaultControlUiDeviceToken(): String {
    gatewayEnsureDeviceToken(GATEWAY_DEVICE_AUTH_DEFAULT_DEVICE_ID, displayName: "Metis Control UI")
}

public func gatewayVerifyDeviceToken(deviceId: String, token: String): Bool {
    let normalized = deviceId.trimAscii()
    let value = token.trimAscii()
    if (normalized.isEmpty() || value.isEmpty()) {
        return false
    }
    let root = readGatewayDeviceRegistry()
    match (root.get(normalized)) {
        case Some(v) =>
            try {
                let obj = v.asObject()
                match (obj.get("token")) {
                    case Some(tok) => tok.asString().getValue().trimAscii() == value
                    case None => false
                }
            } catch (_e: Exception) {
                false
            }
        case None => false
    }
}

public func gatewayBuildDeviceAuthPayload(
    deviceId: String,
    clientId: String,
    clientMode: String,
    role: String,
    scopes: Array<String>,
    token!: String = "",
    nonce!: String = "local",
    platform!: String = "",
    deviceFamily!: String = ""
): String {
    let scopeString = String.join(scopes, delimiter: ",")
    "v3|${deviceId}|${clientId}|${clientMode}|${role}|${scopeString}|${gatewayNowMsForDeviceAuth()}|${token}|${nonce}|${platform}|${deviceFamily}"
}
