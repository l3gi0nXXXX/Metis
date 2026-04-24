package metis.gateway.runtime


import metis.core.config.CliConfig
import metis.gateway.config.{getGatewayPluginCatalogEntry, normalizeGatewayChannelId}
import metis.utils.ShellUtils
import magic.jsonable.*

import std.env.getVariable
import std.time.*
import std.fs.{Directory, File, Path, exists}

import stdx.encoding.json.{JsonObject, JsonString, JsonValue}

private func gatewayLegacyPluginHostRoot(pluginId: String): Option<(Path, Path)> {
    let normalized = normalizeGatewayChannelId(pluginId)
    let root = CliConfig.dotDir.join("gateway-plugins")
    if (!exists(root)) {
        return None
    }
    try {
        for (entry in Directory.readFrom(root)) {
            if (!entry.isDirectory()) {
                continue
            }
            let pluginRoot = root.join(entry.name)
            let manifestPath = pluginRoot.join("metis.plugin.json")
            if (!exists(manifestPath)) {
                continue
            }
            let raw = String.fromUtf8(File.readFrom(manifestPath))
            let obj = JsonValue.fromStr(raw).asObject()
            match (obj.get("id")) {
                case Some(v) =>
                    try {
                        let manifestId = normalizeGatewayChannelId(v.asString().getValue())
                        if (manifestId == normalized) {
                            return Some((pluginRoot, manifestPath))
                        }
                    } catch (_e: Exception) {
                        ()
                    }
                case None => ()
            }
        }
    } catch (_e: Exception) {
        ()
    }
    None
}

private func gatewayLegacyPluginHostScript(): String {
    let root = match (getVariable("METIS_CJPM_ROOT")) {
        case Some(v) =>
            let trimmed = v.trimAscii()
            if (trimmed.isEmpty()) { CliConfig.cwd.toString() } else { trimmed }
        case None => CliConfig.cwd.toString()
    }
    Path(root).join("scripts").join("legacy-channel-host.mjs").toString()
}

private func gatewayLegacyPluginJsonObject(raw: String): JsonObject {
    let text = raw.trimAscii()
    if (text.isEmpty()) {
        return JsonObject()
    }
    try {
        return JsonValue.fromStr(text).asObject()
    } catch (_e: Exception) {
        let out = JsonObject()
        out.put("raw", JsonString(text))
        out.put("parseError", JsonString("invalid-json"))
        return out
    }
}

private func gatewayLegacyPluginHostError(
    pluginId: String,
    op: String,
    stderr: String,
    exitCode: Int64,
    reason: String
): JsonObject {
    let out = JsonObject()
    out.put("pluginId", JsonString(normalizeGatewayChannelId(pluginId)))
    out.put("operation", JsonString(op))
    out.put("hostError", JsonString(reason))
    out.put("stderr", JsonString(stderr.trimAscii()))
    out.put("exitCode", exitCode.toJsonValue())
    out.put("compatibilityMode", JsonString("legacy-plugin-host"))
    out
}

public func gatewayLegacyPluginHostCompatible(pluginId: String): Bool {
    match (getGatewayPluginCatalogEntry(pluginId)) {
        case Some(entry) => entry.compatibilityMode == "legacy-plugin-host"
        case None => false
    }
}

public func gatewayLegacyPluginHostInvoke(
    pluginId: String,
    op: String,
    config!: JsonValue = JsonObject(),
    timeoutMs!: Int64 = 10000,
    accountId!: String = ""
): JsonObject {
    if (!gatewayLegacyPluginHostCompatible(pluginId)) {
        return JsonObject()
    }
    match (gatewayLegacyPluginHostRoot(pluginId)) {
        case Some(pair) =>
            let pluginRoot = pair[0]
            let manifestPath = pair[1]
            let args = [
                "node",
                gatewayLegacyPluginHostScript(),
                op,
                "--plugin-id",
                normalizeGatewayChannelId(pluginId),
                "--channel-id",
                normalizeGatewayChannelId(pluginId),
                "--plugin-root",
                pluginRoot.toString(),
                "--manifest-path",
                manifestPath.toString(),
                "--compat-mode",
                "legacy-node-plugin",
                "--config-json",
                config.toJsonString(),
                "--timeout-ms",
                "${max(1000, timeoutMs)}",
                "--account-id",
                accountId.trimAscii()
            ]
            let timeout = Some(Duration.millisecond * max(1000, timeoutMs))
            let (ec, out, err) = try {
                ShellUtils.execute(args, timeout: timeout, withWrap: false, workDir: pluginRoot)
            } catch (e: Exception) {
                return gatewayLegacyPluginHostError(pluginId, op, e.message, 1, "host-exception")
            }
            if (ec != 0 && out.trimAscii().isEmpty()) {
                return gatewayLegacyPluginHostError(pluginId, op, err, ec, "host-failed")
            }
            let result = gatewayLegacyPluginJsonObject(out)
            result.put("hostOperation", JsonString(op))
            result.put("pluginId", JsonString(normalizeGatewayChannelId(pluginId)))
            result.put("compatibilityMode", JsonString("legacy-plugin-host"))
            if (!err.trimAscii().isEmpty()) {
                result.put("hostStderr", JsonString(err.trimAscii()))
            }
            result
        case None =>
            gatewayLegacyPluginHostError(pluginId, op, "", 1, "manifest-not-found")
    }
}

public func gatewayLegacyPluginHostInspect(
    pluginId: String,
    config!: JsonValue = JsonObject(),
    timeoutMs!: Int64 = 20000
): JsonObject {
    gatewayLegacyPluginHostInvoke(pluginId, "inspect", config: config, timeoutMs: timeoutMs)
}

public func gatewayLegacyPluginHostProbe(
    pluginId: String,
    config!: JsonValue = JsonObject(),
    timeoutMs!: Int64 = 10000,
    accountId!: String = ""
): JsonObject {
    gatewayLegacyPluginHostInvoke(pluginId, "probe", config: config, timeoutMs: timeoutMs, accountId: accountId)
}

public func gatewayLegacyPluginHostAudit(
    pluginId: String,
    config!: JsonValue = JsonObject(),
    timeoutMs!: Int64 = 10000,
    accountId!: String = ""
): JsonObject {
    gatewayLegacyPluginHostInvoke(pluginId, "audit", config: config, timeoutMs: timeoutMs, accountId: accountId)
}

public func gatewayLegacyPluginHostPackageState(pluginId: String, config!: JsonValue = JsonObject()): JsonObject {
    gatewayLegacyPluginHostInvoke(pluginId, "package-state", config: config)
}

public func gatewayLegacyPluginHostSetup(pluginId: String, config!: JsonValue = JsonObject()): JsonObject {
    gatewayLegacyPluginHostInvoke(pluginId, "setup", config: config)
}

public func gatewayLegacyPluginHostSetupRegistry(pluginId: String, config!: JsonValue = JsonObject()): JsonObject {
    gatewayLegacyPluginHostInvoke(pluginId, "setup-registry", config: config)
}

public func gatewayLegacyPluginHostApplySetup(pluginId: String, config!: JsonValue = JsonObject()): JsonObject {
    gatewayLegacyPluginHostInvoke(pluginId, "apply-setup", config: config)
}

public func gatewayLegacyPluginHostRuntimeForwarders(pluginId: String, config!: JsonValue = JsonObject()): JsonObject {
    gatewayLegacyPluginHostInvoke(pluginId, "runtime-forwarders", config: config)
}

public func gatewayLegacyPluginHostResolveAccount(
    pluginId: String,
    config!: JsonValue = JsonObject(),
    accountId!: String = ""
): JsonObject {
    gatewayLegacyPluginHostInvoke(pluginId, "resolve-account", config: config, accountId: accountId)
}

public func gatewayLegacyPluginHostAccounts(pluginId: String, config!: JsonValue = JsonObject()): JsonObject {
    gatewayLegacyPluginHostInvoke(pluginId, "accounts", config: config)
}

public func gatewayLegacyPluginHostBindings(pluginId: String, config!: JsonValue = JsonObject()): JsonObject {
    gatewayLegacyPluginHostInvoke(pluginId, "bindings", config: config)
}

public func gatewayLegacyPluginHostConfiguredBindings(pluginId: String, config!: JsonValue = JsonObject()): JsonObject {
    gatewayLegacyPluginHostInvoke(pluginId, "configured-bindings", config: config)
}

public func gatewayLegacyPluginHostConfiguredBindingsSummary(pluginId: String, config!: JsonValue = JsonObject()): JsonObject {
    gatewayLegacyPluginHostInvoke(pluginId, "configured-bindings-summary", config: config)
}

public func gatewayLegacyPluginHostDirectory(
    pluginId: String,
    config!: JsonValue = JsonObject(),
    accountId!: String = "",
    groupId!: String = ""
): JsonObject {
    if (!gatewayLegacyPluginHostCompatible(pluginId)) {
        return JsonObject()
    }
    match (gatewayLegacyPluginHostRoot(pluginId)) {
        case Some(pair) =>
            let pluginRoot = pair[0]
            let manifestPath = pair[1]
            let args = [
                "node",
                gatewayLegacyPluginHostScript(),
                "directory",
                "--plugin-id",
                normalizeGatewayChannelId(pluginId),
                "--channel-id",
                normalizeGatewayChannelId(pluginId),
                "--plugin-root",
                pluginRoot.toString(),
                "--manifest-path",
                manifestPath.toString(),
                "--compat-mode",
                "legacy-node-plugin",
                "--config-json",
                config.toJsonString(),
                "--timeout-ms",
                "10000",
                "--account-id",
                accountId.trimAscii(),
                "--group-id",
                groupId.trimAscii()
            ]
            let (ec, out, err) = try {
                ShellUtils.execute(args, timeout: Some(Duration.millisecond * 10000), withWrap: false, workDir: pluginRoot)
            } catch (e: Exception) {
                return gatewayLegacyPluginHostError(pluginId, "directory", e.message, 1, "host-exception")
            }
            if (ec != 0 && out.trimAscii().isEmpty()) {
                return gatewayLegacyPluginHostError(pluginId, "directory", err, ec, "host-failed")
            }
            let result = gatewayLegacyPluginJsonObject(out)
            result.put("hostOperation", JsonString("directory"))
            result.put("pluginId", JsonString(normalizeGatewayChannelId(pluginId)))
            result.put("compatibilityMode", JsonString("legacy-plugin-host"))
            if (!err.trimAscii().isEmpty()) {
                result.put("hostStderr", JsonString(err.trimAscii()))
            }
            result
        case None =>
            gatewayLegacyPluginHostError(pluginId, "directory", "", 1, "manifest-not-found")
    }
}

public func gatewayLegacyPluginHostTargets(
    pluginId: String,
    target: String,
    config!: JsonValue = JsonObject(),
    accountId!: String = ""
): JsonObject {
    if (!gatewayLegacyPluginHostCompatible(pluginId)) {
        return JsonObject()
    }
    match (gatewayLegacyPluginHostRoot(pluginId)) {
        case Some(pair) =>
            let pluginRoot = pair[0]
            let manifestPath = pair[1]
            let args = [
                "node",
                gatewayLegacyPluginHostScript(),
                "targets",
                "--plugin-id",
                normalizeGatewayChannelId(pluginId),
                "--channel-id",
                normalizeGatewayChannelId(pluginId),
                "--plugin-root",
                pluginRoot.toString(),
                "--manifest-path",
                manifestPath.toString(),
                "--compat-mode",
                "legacy-node-plugin",
                "--config-json",
                config.toJsonString(),
                "--timeout-ms",
                "10000",
                "--account-id",
                accountId.trimAscii(),
                "--target",
                target
            ]
            let (ec, out, err) = try {
                ShellUtils.execute(args, timeout: Some(Duration.millisecond * 10000), withWrap: false, workDir: pluginRoot)
            } catch (e: Exception) {
                return gatewayLegacyPluginHostError(pluginId, "targets", e.message, 1, "host-exception")
            }
            if (ec != 0 && out.trimAscii().isEmpty()) {
                return gatewayLegacyPluginHostError(pluginId, "targets", err, ec, "host-failed")
            }
            let result = gatewayLegacyPluginJsonObject(out)
            result.put("hostOperation", JsonString("targets"))
            result.put("pluginId", JsonString(normalizeGatewayChannelId(pluginId)))
            result.put("compatibilityMode", JsonString("legacy-plugin-host"))
            if (!err.trimAscii().isEmpty()) {
                result.put("hostStderr", JsonString(err.trimAscii()))
            }
            result
        case None =>
            gatewayLegacyPluginHostError(pluginId, "targets", "", 1, "manifest-not-found")
    }
}

public func gatewayLegacyPluginHostStatus(
    pluginId: String,
    config!: JsonValue = JsonObject(),
    timeoutMs!: Int64 = 10000,
    accountId!: String = ""
): JsonObject {
    gatewayLegacyPluginHostInvoke(pluginId, "status", config: config, timeoutMs: timeoutMs, accountId: accountId)
}

public func gatewayLegacyPluginHostActions(
    pluginId: String,
    config!: JsonValue = JsonObject(),
    accountId!: String = ""
): JsonObject {
    gatewayLegacyPluginHostInvoke(pluginId, "actions", config: config, accountId: accountId)
}

public func gatewayLegacyPluginHostDispatchAction(
    pluginId: String,
    action: String,
    payload!: JsonValue = JsonObject(),
    config!: JsonValue = JsonObject(),
    accountId!: String = ""
): JsonObject {
    if (!gatewayLegacyPluginHostCompatible(pluginId)) {
        return JsonObject()
    }
    match (gatewayLegacyPluginHostRoot(pluginId)) {
        case Some(pair) =>
            let pluginRoot = pair[0]
            let manifestPath = pair[1]
            let args = [
                "node",
                gatewayLegacyPluginHostScript(),
                "dispatch-action",
                "--plugin-id",
                normalizeGatewayChannelId(pluginId),
                "--channel-id",
                normalizeGatewayChannelId(pluginId),
                "--plugin-root",
                pluginRoot.toString(),
                "--manifest-path",
                manifestPath.toString(),
                "--compat-mode",
                "legacy-node-plugin",
                "--config-json",
                config.toJsonString(),
                "--timeout-ms",
                "10000",
                "--account-id",
                accountId.trimAscii(),
                "--action",
                action,
                "--payload-json",
                payload.toJsonString()
            ]
            let (ec, out, err) = try {
                ShellUtils.execute(args, timeout: Some(Duration.millisecond * 10000), withWrap: false, workDir: pluginRoot)
            } catch (e: Exception) {
                return gatewayLegacyPluginHostError(pluginId, "dispatch-action", e.message, 1, "host-exception")
            }
            if (ec != 0 && out.trimAscii().isEmpty()) {
                return gatewayLegacyPluginHostError(pluginId, "dispatch-action", err, ec, "host-failed")
            }
            let result = gatewayLegacyPluginJsonObject(out)
            result.put("hostOperation", JsonString("dispatch-action"))
            result.put("pluginId", JsonString(normalizeGatewayChannelId(pluginId)))
            result.put("compatibilityMode", JsonString("legacy-plugin-host"))
            if (!err.trimAscii().isEmpty()) {
                result.put("hostStderr", JsonString(err.trimAscii()))
            }
            result
        case None =>
            gatewayLegacyPluginHostError(pluginId, "dispatch-action", "", 1, "manifest-not-found")
    }
}

public func gatewayLegacyPluginHostStart(
    pluginId: String,
    config!: JsonValue = JsonObject(),
    accountId!: String = ""
): JsonObject {
    gatewayLegacyPluginHostInvoke(pluginId, "start", config: config, accountId: accountId)
}

public func gatewayLegacyPluginHostStop(
    pluginId: String,
    config!: JsonValue = JsonObject(),
    accountId!: String = ""
): JsonObject {
    gatewayLegacyPluginHostInvoke(pluginId, "stop", config: config, accountId: accountId)
}

public func gatewayLegacyPluginHostSend(
    pluginId: String,
    peerId: String,
    text: String,
    replyTo!: String = "",
    config!: JsonValue = JsonObject(),
    accountId!: String = ""
): JsonObject {
    if (!gatewayLegacyPluginHostCompatible(pluginId)) {
        return JsonObject()
    }
    match (gatewayLegacyPluginHostRoot(pluginId)) {
        case Some(pair) =>
            let pluginRoot = pair[0]
            let manifestPath = pair[1]
            let args = [
                "node",
                gatewayLegacyPluginHostScript(),
                "send",
                "--plugin-id",
                normalizeGatewayChannelId(pluginId),
                "--channel-id",
                normalizeGatewayChannelId(pluginId),
                "--plugin-root",
                pluginRoot.toString(),
                "--manifest-path",
                manifestPath.toString(),
                "--compat-mode",
                "legacy-node-plugin",
                "--config-json",
                config.toJsonString(),
                "--timeout-ms",
                "10000",
                "--account-id",
                accountId.trimAscii(),
                "--peer-id",
                peerId,
                "--text",
                text,
                "--reply-to",
                replyTo
            ]
            let (ec, out, err) = try {
                ShellUtils.execute(args, timeout: Some(Duration.millisecond * 10000), withWrap: false, workDir: pluginRoot)
            } catch (e: Exception) {
                return gatewayLegacyPluginHostError(pluginId, "send", e.message, 1, "host-exception")
            }
            if (ec != 0 && out.trimAscii().isEmpty()) {
                return gatewayLegacyPluginHostError(pluginId, "send", err, ec, "host-failed")
            }
            let result = gatewayLegacyPluginJsonObject(out)
            result.put("hostOperation", JsonString("send"))
            result.put("pluginId", JsonString(normalizeGatewayChannelId(pluginId)))
            result.put("compatibilityMode", JsonString("legacy-plugin-host"))
            if (!err.trimAscii().isEmpty()) {
                result.put("hostStderr", JsonString(err.trimAscii()))
            }
            result
        case None =>
            gatewayLegacyPluginHostError(pluginId, "send", "", 1, "manifest-not-found")
    }
}

public func gatewayLegacyPluginHostLogout(
    pluginId: String,
    config!: JsonValue = JsonObject(),
    accountId!: String = ""
): JsonObject {
    gatewayLegacyPluginHostInvoke(pluginId, "logout", config: config, accountId: accountId)
}
