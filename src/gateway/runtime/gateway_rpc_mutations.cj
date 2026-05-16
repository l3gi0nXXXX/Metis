package metis.gateway.runtime

import magic.jsonable.*

import metis.core.config.{CliSettingManager, MetisConfigManager}

import stdx.encoding.json.*

private func parseGatewayBoolWord(raw: String): Option<Bool> {
    let t = raw.trimAscii().toAsciiLower()
    if (t == "true" || t == "1" || t == "yes" || t == "on") {
        return Some(true)
    }
    if (t == "false" || t == "0" || t == "no" || t == "off") {
        return Some(false)
    }
    None
}

private func gatewayEnsureObject(root: JsonObject, key: String): JsonObject {
    match (root.get(key)) {
        case Some(value) =>
            try {
                value.asObject()
            } catch (_e: Exception) {
                let obj = JsonObject()
                root.put(key, obj)
                obj
            }
        case None =>
            let obj = JsonObject()
            root.put(key, obj)
            obj
    }
}

private func gatewayJsonObjectAt(obj: JsonObject, path: Array<String>): Option<JsonObject> {
    var current = obj
    for (key in path) {
        match (current.get(key)) {
            case Some(value) =>
                try {
                    current = value.asObject()
                } catch (_e: Exception) {
                    return None
                }
            case None =>
                return None
        }
    }
    Some(current)
}

private func gatewayDreamingEnabledPatchValue(raw: String): Option<Bool> {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return None
    }
    let patchRoot = try {
        JsonValue.fromStr(trimmed).asObject()
    } catch (_e: Exception) {
        return None
    }
    let dreaming = match (gatewayJsonObjectAt(patchRoot, ["plugins", "entries", "memory-core", "config", "dreaming"])) {
        case Some(value) => value
        case None => return None
    }
    match (dreaming.get("enabled")) {
        case Some(value) =>
            try {
                Some(value.asBool().getValue())
            } catch (_e: Exception) {
                None
            }
        case None =>
            None
    }
}

private func applyGatewayConfigObjectPatch(raw: String): (Bool, String) {
    let dreamingEnabled = match (gatewayDreamingEnabledPatchValue(raw)) {
        case Some(value) => value
        case None =>
            let replacement = try {
                JsonValue.fromStr(raw.trimAscii()).asObject()
            } catch (_e: Exception) {
                return (false, "config.patch requires a non-empty path unless the raw object patch is a supported control-ui partial update or full config root")
            }
            if (replacement.get("agents").isSome() || replacement.get("gateway").isSome()) {
                MetisConfigManager.writeRoot(replacement)
                CliSettingManager.applyPersistedFieldsToCliConfig()
                return (true, "config root replaced")
            }
            return (false, "config.patch requires a non-empty path unless the raw object patch is a supported control-ui partial update or full config root")
    }
    MetisConfigManager.initializeIfMissing()
    let currentRoot = match (MetisConfigManager.rawConfig()) {
        case Some(root) => root
        case None => JsonObject()
    }
    let plugins = gatewayEnsureObject(currentRoot, "plugins")
    let entries = gatewayEnsureObject(plugins, "entries")
    let memoryCore = gatewayEnsureObject(entries, "memory-core")
    let config = gatewayEnsureObject(memoryCore, "config")
    let dreaming = gatewayEnsureObject(config, "dreaming")
    dreaming.put("enabled", dreamingEnabled.toJsonValue())
    MetisConfigManager.writeRoot(currentRoot)
    CliSettingManager.applyPersistedFieldsToCliConfig()
    (true, "config object patch merged: plugins.entries.memory-core.config.dreaming.enabled")
}

private func gatewayConfigPatchJsonObjectValue(raw: String): Option<JsonObject> {
    try {
        Some(JsonValue.fromStr(raw.trimAscii()).asObject())
    } catch (_e: Exception) {
        None
    }
}

public func applyGatewayConfigPatch(path: String, raw: String): (Bool, String) {
    let normalized = path.trimAscii().toAsciiLower()
    let value = raw.trimAscii()
    if (normalized.isEmpty()) {
        return applyGatewayConfigObjectPatch(value)
    }
    var g = CliSettingManager.readGatewaySettings()
    match (normalized) {
        case "enabled" | "gateway.enabled" =>
            match (parseGatewayBoolWord(value)) {
                case Some(v) =>
                    g.enabled = v
                    CliSettingManager.writeGatewaySettings(g)
                    return (true, "gateway.enabled updated")
                case None => return (false, "gateway.enabled requires a bool value")
            }
        case "session.dmscope" | "gateway.session.dmscope" =>
            g.session.dmScope = value
            CliSettingManager.writeGatewaySettings(g)
            return (true, "gateway.session.dmScope updated")
        case "session.persistenceenabled" | "gateway.session.persistenceenabled" =>
            match (parseGatewayBoolWord(value)) {
                case Some(v) =>
                    g.session.persistenceEnabled = v
                    CliSettingManager.writeGatewaySettings(g)
                    return (true, "gateway.session.persistenceEnabled updated")
                case None => return (false, "gateway.session.persistenceEnabled requires a bool value")
            }
        case "controlui.enabled" | "gateway.controlui.enabled" =>
            match (parseGatewayBoolWord(value)) {
                case Some(v) =>
                    g.controlUi.enabled = v
                    CliSettingManager.writeGatewaySettings(g)
                    return (true, "gateway.controlUi.enabled updated")
                case None => return (false, "gateway.controlUi.enabled requires a bool value")
            }
        case "controlui.basepath" | "gateway.controlui.basepath" =>
            g.controlUi.basePath = value
            CliSettingManager.writeGatewaySettings(g)
            return (true, "gateway.controlUi.basePath updated")
        case "controlui.root" | "gateway.controlui.root" =>
            g.controlUi.root = value
            CliSettingManager.writeGatewaySettings(g)
            return (true, "gateway.controlUi.root updated")
        case "controlui.allowinsecureauth" | "gateway.controlui.allowinsecureauth" =>
            match (parseGatewayBoolWord(value)) {
                case Some(v) =>
                    g.controlUi.allowInsecureAuth = v
                    CliSettingManager.writeGatewaySettings(g)
                    return (true, "gateway.controlUi.allowInsecureAuth updated")
                case None => return (false, "gateway.controlUi.allowInsecureAuth requires a bool value")
            }
        case "controlui.dangerouslydisabledeviceauth" | "gateway.controlui.dangerouslydisabledeviceauth" =>
            match (parseGatewayBoolWord(value)) {
                case Some(v) =>
                    g.controlUi.dangerouslyDisableDeviceAuth = v
                    CliSettingManager.writeGatewaySettings(g)
                    return (true, "gateway.controlUi.dangerouslyDisableDeviceAuth updated")
                case None => return (false, "gateway.controlUi.dangerouslyDisableDeviceAuth requires a bool value")
            }
        case "auth.mode" | "gateway.auth.mode" =>
            let normalizedAuthMode = value.toAsciiLower()
            if (normalizedAuthMode != "token" && normalizedAuthMode != "password" && normalizedAuthMode != "trusted-proxy") {
                return (false, "gateway.auth.mode must be token, password, or trusted-proxy")
            }
            g.auth.mode = normalizedAuthMode
            CliSettingManager.writeGatewaySettings(g)
            return (true, "gateway.auth.mode updated")
        case "auth.allowtailscale" | "gateway.auth.allowtailscale" =>
            match (parseGatewayBoolWord(value)) {
                case Some(v) =>
                    g.auth.allowTailscale = v
                    CliSettingManager.writeGatewaySettings(g)
                    return (true, "gateway.auth.allowTailscale updated")
                case None => return (false, "gateway.auth.allowTailscale requires a bool value")
            }
        case "feishu.enabled" | "gateway.feishu.enabled" =>
            match (parseGatewayBoolWord(value)) {
                case Some(v) =>
                    g.feishu.enabled = v
                    CliSettingManager.writeGatewaySettings(g)
                    return (true, "gateway.feishu.enabled updated")
                case None => return (false, "gateway.feishu.enabled requires a bool value")
            }
        case "feishu.appid" | "gateway.feishu.appid" =>
            g.feishu.appId = value
            CliSettingManager.writeGatewaySettings(g)
            return (true, "gateway.feishu.appId updated")
        case "feishu.appsecret" | "gateway.feishu.appsecret" =>
            g.feishu.appSecret = value
            CliSettingManager.writeGatewaySettings(g)
            return (true, "gateway.feishu.appSecret updated")
        case "feishu.receivemode" | "gateway.feishu.receivemode" =>
            g.feishu.receiveMode = value
            CliSettingManager.writeGatewaySettings(g)
            return (true, "gateway.feishu.receiveMode updated")
        case "qq.enabled" | "gateway.qq.enabled" =>
            match (parseGatewayBoolWord(value)) {
                case Some(v) =>
                    g.qq.enabled = v
                    CliSettingManager.writeGatewaySettings(g)
                    return (true, "gateway.qq.enabled updated")
                case None => return (false, "gateway.qq.enabled requires a bool value")
            }
        case "qq.mode" | "gateway.qq.mode" =>
            if (value.trimAscii().toAsciiLower() != "official_ws") {
                return (false, "gateway.qq.mode currently only supports official_ws")
            }
            g.qq.mode = "official_ws"
            CliSettingManager.writeGatewaySettings(g)
            return (true, "gateway.qq.mode updated")
        case "qq.appid" | "gateway.qq.appid" =>
            g.qq.appId = value
            CliSettingManager.writeGatewaySettings(g)
            return (true, "gateway.qq.appId updated")
        case "qq.appsecret" | "gateway.qq.appsecret" =>
            g.qq.appSecret = value
            CliSettingManager.writeGatewaySettings(g)
            return (true, "gateway.qq.appSecret updated")
        case "telegram.enabled" | "gateway.telegram.enabled" =>
            match (parseGatewayBoolWord(value)) {
                case Some(v) =>
                    g.telegram.enabled = v
                    CliSettingManager.writeGatewaySettings(g)
                    return (true, "gateway.telegram.enabled updated")
                case None => return (false, "gateway.telegram.enabled requires a bool value")
            }
        case "telegram.bottoken" | "gateway.telegram.bottoken" =>
            g.telegram.botToken = value
            CliSettingManager.writeGatewaySettings(g)
            return (true, "gateway.telegram.botToken updated")
        case "telegram.webhookurl" | "gateway.telegram.webhookurl" =>
            g.telegram.webhookUrl = value
            CliSettingManager.writeGatewaySettings(g)
            return (true, "gateway.telegram.webhookUrl updated")
        case "agents.defaults.imagemodel.primary" =>
            if (value.isEmpty()) {
                return (false, "agents.defaults.imageModel.primary requires a model ref")
            }
            MetisConfigManager.setImageModelRef(value)
            return (true, "agents.defaults.imageModel.primary updated")
        case "gateway.media.image" =>
            match (gatewayConfigPatchJsonObjectValue(value)) {
                case Some(obj) =>
                    g.media.image = obj
                    CliSettingManager.writeGatewaySettings(g)
                    return (true, "gateway.media.image updated")
                case None => return (false, "gateway.media.image requires a JSON object")
            }
        case "gateway.telegram.image" =>
            match (gatewayConfigPatchJsonObjectValue(value)) {
                case Some(obj) =>
                    g.telegram.image = obj
                    CliSettingManager.writeGatewaySettings(g)
                    return (true, "gateway.telegram.image updated")
                case None => return (false, "gateway.telegram.image requires a JSON object")
            }
        case "gateway.feishu.image" =>
            match (gatewayConfigPatchJsonObjectValue(value)) {
                case Some(obj) =>
                    g.feishu.image = obj
                    CliSettingManager.writeGatewaySettings(g)
                    return (true, "gateway.feishu.image updated")
                case None => return (false, "gateway.feishu.image requires a JSON object")
            }
        case "gateway.qq.image" =>
            match (gatewayConfigPatchJsonObjectValue(value)) {
                case Some(obj) =>
                    g.qq.image = obj
                    CliSettingManager.writeGatewaySettings(g)
                    return (true, "gateway.qq.image updated")
                case None => return (false, "gateway.qq.image requires a JSON object")
            }
        case _ =>
            return (false, "Unsupported gateway config patch path: ${path.trimAscii()}")
    }
}
