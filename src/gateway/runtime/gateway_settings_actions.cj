package metis.gateway.runtime

import metis.core.config.{CliConfig, CliSettingManager, GatewayPluginUserSettings}
import metis.gateway.config.{buildGatewayConfigFromUserSettings, builtinGatewayChannelIds, gatewayChannelCatalogJson, gatewayPluginCatalogJson, mergeGatewayUserSettings, registeredGatewayPluginIds}
import metis.io.PrintUtils
import metis.utils.ShellUtils

import std.collection.{ArrayList, HashMap}
import std.convert.Parsable
import std.fs.{Path, Directory, File, exists}

import stdx.encoding.json.{JsonObject, JsonString, JsonValue}

/**
 * 供 `gateway` 子命令与交互式 `/Metis` 共用的网关配置操作（逻辑与 gateway_cli 一致）。
 */
public func gatewayActionsMaskSecret(s: String): String {
    if (s.isEmpty()) {
        return ""
    }
    "***"
}

public func gatewayActionsParseBoolWord(w: String): Option<Bool> {
    let x = w.trimAscii().toAsciiLower()
    if (x == "true" || x == "1" || x == "yes" || x == "on") {
        return Some(true)
    }
    if (x == "false" || x == "0" || x == "no" || x == "off") {
        return Some(false)
    }
    None
}

public func gatewayActionsPrintStatus(): Unit {
    let g = CliSettingManager.readGatewaySettings()
    let cfg = buildGatewayConfigFromUserSettings(g)
    let (fCfg, qCfg, tCfg) = mergeGatewayUserSettings(g)
    let controlUiSnapshot = gatewayControlUiSnapshotJson(cfg)
    let controlUiRootState = gatewayControlUiRootStateJson(cfg)
    let controlUiAssetMode = match (controlUiSnapshot.get("assetMode")) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { "inline-fallback" }
        case None => "inline-fallback"
    }
    let controlUiRootKind = match (controlUiRootState.get("kind")) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
    let controlUiRootMessage = match (controlUiRootState.get("message")) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
    PrintUtils.printLine("配置文件 gateway 段（文件内开关，不含环境变量覆盖）：")
    PrintUtils.printLine("  master(enabled): ${g.enabled}")
    PrintUtils.printLine(
        "  bind/port/mode: bind=${cfg.bind} port=${cfg.port} mode=${cfg.mode} customBindHost=${cfg.customBindHost}"
    )
    PrintUtils.printLine(
        "  session.dmScope: ${g.session.dmScope}  session.persistenceEnabled: ${g.session.persistenceEnabled}"
    )
    PrintUtils.printLine(
        "  discovery: wideArea.enabled=${cfg.discovery.wideArea.enabled} wideArea.domain=${cfg.discovery.wideArea.domain} mdns.mode=${cfg.discovery.mdns.mode}"
    )
    PrintUtils.printLine(
        "  tls: enabled=${cfg.tls.enabled} autoGenerate=${cfg.tls.autoGenerate} certPath=${cfg.tls.certPath} keyPath=${cfg.tls.keyPath}"
    )
    PrintUtils.printLine(
        "  auth: mode=${cfg.auth.mode} allowTailscale=${cfg.auth.allowTailscale} trustedProxies=${g.trustedProxies.size} allowRealIpFallback=${g.allowRealIpFallback}"
    )
    PrintUtils.printLine(
        "  controlUi/http: controlUi.enabled=${cfg.controlUi.enabled} chatCompletions.enabled=${cfg.http.endpoints.chatCompletions.enabled} responses.enabled=${cfg.http.endpoints.responses.enabled}"
    )
    PrintUtils.printLine(
        "  controlUi assets: mode=${controlUiAssetMode} root=${cfg.controlUi.root} rootState=${controlUiRootKind}"
    )
    if (!controlUiRootMessage.trimAscii().isEmpty()) {
        PrintUtils.printLine("  controlUi assets detail: ${controlUiRootMessage}")
    }
    if (controlUiAssetMode == "inline-fallback") {
        PrintUtils.printLine("  controlUi recommendation: keep bundled static assets available or configure gateway.controlUi.root to a built static UI directory; inline fallback is legacy-only.")
    }
    PrintUtils.printLine(
        "  remote/reload: remote.enabled=${cfg.remote.enabled} remote.transport=${cfg.remote.transport} reload.mode=${cfg.reload.mode}"
    )
    PrintUtils.printLine(
        "  nodes/canvas/talk/webchat: browser.mode=${cfg.nodes.browser.mode} canvas.enabled=${cfg.canvas.enabled} talk.provider=${cfg.talk.provider} webchat.chatHistoryMaxChars=${cfg.webchat.chatHistoryMaxChars}"
    )
    PrintUtils.printLine(
        "  channel runtime: healthCheck=${cfg.channelHealthCheckMinutes} staleThreshold=${cfg.channelStaleEventThresholdMinutes} maxRestartsPerHour=${cfg.channelMaxRestartsPerHour}"
    )
    PrintUtils.printLine(
        "  feishu.enabled: ${g.feishu.enabled}  appId=${g.feishu.appId}  appSecret=${gatewayActionsMaskSecret(g.feishu.appSecret)}"
    )
    PrintUtils.printLine(
        "  qq.enabled: ${g.qq.enabled}  mode=${g.qq.mode}  appId=${g.qq.appId}  appSecret=${gatewayActionsMaskSecret(g.qq.appSecret)}"
    )
    PrintUtils.printLine("合并环境变量后的有效开关（实际启动行为）：")
    PrintUtils.printLine("  feishu 有效: ${fCfg.enabled}")
    PrintUtils.printLine("  qq 有效: ${qCfg.enabled}")
    if (g.gatewayPlugins.isEmpty()) {
        PrintUtils.printLine("  gatewayPlugins: （空）")
    } else {
        PrintUtils.printLine("  gatewayPlugins:")
        for (p in g.gatewayPlugins) {
            PrintUtils.printLine("    - id=${p.id} enabled=${p.enabled}")
        }
    }
}

public func gatewayActionsPrintChannelsHelp(): Unit {
    PrintUtils.printLine("Gateway channels")
    PrintUtils.printLine("Meaning: builtin=shipped with Metis, plugin=installed external channel, enabled=config switch.")
    PrintUtils.printLine("Built-in:")
    for (id in builtinGatewayChannelIds()) {
        PrintUtils.printLine("  - ${id}")
    }
    let reg = registeredGatewayPluginIds()
    if (reg.size > 0) {
        PrintUtils.printLine("Registered plugins:")
        for (id in reg) {
            PrintUtils.printLine("  - ${id}")
        }
    } else {
        PrintUtils.printLine("Registered plugins: (none)")
    }
    let installed = gatewayActionsDiscoverInstalledPluginIds()
    if (installed.isEmpty()) {
        PrintUtils.printLine("Installed plugins: (none)")
    } else {
        PrintUtils.printLine("Installed plugins:")
        for (id in installed) {
            PrintUtils.printLine("  - ${id}")
        }
    }
    PrintUtils.printLine("Next: use `gateway discover` for runtime details, `gateway channel enable <id>` or `gateway channel disable <id>` to change built-in channel switches.")
}

/** 扫描 `~/.metis/gateway-plugins/xx/` 下的兼容 manifest，提取 `id`。 */
public func gatewayActionsDiscoverInstalledPluginIds(): Array<String> {
    let out = ArrayList<String>()
    let root = CliConfig.dotDir.join("gateway-plugins")
    if (!exists(root)) {
        return out.toArray()
    }
    try {
        for (entry in Directory.readFrom(root)) {
            if (!entry.isDirectory()) {
                continue
            }
            let manifest = root.join(entry.name).join("metis.plugin.json")
            if (!exists(manifest)) {
                continue
            }
            let id = gatewayActionsReadPluginIdFromManifest(manifest)
            if (!id.isEmpty() && !out.contains(id)) {
                out.add(id)
            }
        }
    } catch (_e: Exception) {
        ()
    }
    out.toArray()
}

private func gatewayActionsReadPluginIdFromManifest(manifestPath: Path): String {
    try {
        let raw = String.fromUtf8(File.readFrom(manifestPath))
        let obj = JsonValue.fromStr(raw).asObject()
        match (obj.get("id")) {
            case Some(v) => v.asString().getValue().trimAscii()
            case None => ""
        }
    } catch (_e: Exception) {
        ""
    }
}

public func gatewayActionsPrintPluginsList(): Unit {
    let installed = gatewayActionsDiscoverInstalledPluginIds()
    let gw = CliSettingManager.readGatewaySettings()
    let enabledById = HashMap<String, Bool>()
    for (p in gw.gatewayPlugins) {
        let pid = p.id.trimAscii()
        if (!pid.isEmpty()) {
            enabledById[pid] = p.enabled
        }
    }
    PrintUtils.printLine("Installed plugins:")
    if (installed.isEmpty()) {
        PrintUtils.printLine("  (none)")
        PrintUtils.printLine("  root=${CliConfig.dotDir.join("gateway-plugins").toString()}")
        return
    }
    for (id in installed) {
        let on = enabledById.get(id) ?? false
        PrintUtils.printLine("  - ${id}  enabled=${on}")
    }
}

public func gatewayActionsPrintPluginSupportedChannels(): Bool {
    let script = CliConfig.cwd.join("tools").join("gateway_plugin_tool").join("install.py")
    if (!exists(script)) {
        PrintUtils.printLine("Install script not found: ${script.toString()}")
        return false
    }
    let (ec, out, err) = ShellUtils.execute(
        ["python", script.toString(), "list"],
        withWrap: false,
        workDir: CliConfig.cwd
    )
    if (ec != 0) {
        PrintUtils.printLine("Plugin listing failed: ${err}")
        return false
    }
    PrintUtils.printLine(out.trimAscii())
    true
}

public func gatewayActionsInstallPlugin(
    nameRaw: String,
    appId!: String = "",
    appSecret!: String = "",
    force!: Bool = false
): Bool {
    let name = nameRaw.trimAscii().toAsciiLower()
    if (name.isEmpty()) {
        PrintUtils.printLine("Usage: gateway plugin install <name> [--app-id <id>] [--app-secret <secret>] [--force]")
        return false
    }
    let script = CliConfig.cwd.join("tools").join("gateway_plugin_tool").join("install.py")
    if (!exists(script)) {
        PrintUtils.printLine("Install script not found: ${script.toString()}")
        return false
    }
    let args = ArrayList<String>(["python", script.toString(), "install", name, "--project-root", CliConfig.cwd.toString()])
    if (!appId.trimAscii().isEmpty()) {
        args.add(all: ["--app-id", appId.trimAscii()])
    }
    if (!appSecret.trimAscii().isEmpty()) {
        args.add(all: ["--app-secret", appSecret.trimAscii()])
    }
    if (force) {
        args.add("--force")
    }
    let (ec, out, err) = ShellUtils.execute(args.toArray(), withWrap: false, workDir: CliConfig.cwd)
    if (ec != 0) {
        PrintUtils.printLine(if (err.trimAscii().isEmpty()) { out.trimAscii() } else { err.trimAscii() })
        return false
    }
    if (!out.trimAscii().isEmpty()) {
        PrintUtils.printLine(out.trimAscii())
    }
    // 自动启用，符合“安装即可用”
    let _ = gatewayActionsSetPluginEnabled(name, true)
    true
}

public func gatewayActionsSetPluginEnabled(idRaw: String, on: Bool): Bool {
    let id = idRaw.trimAscii()
    if (id.isEmpty()) {
        PrintUtils.printLine("Plugin id must not be empty.")
        return false
    }
    let installed = gatewayActionsDiscoverInstalledPluginIds()
    if (!installed.contains(id)) {
        PrintUtils.printLine("Installed plugin not found: ${id} (${CliConfig.dotDir.join("gateway-plugins").toString()})")
        return false
    }
    var g = CliSettingManager.readGatewaySettings()
    let arr = ArrayList<GatewayPluginUserSettings>()
    var updated = false
    for (p in g.gatewayPlugins) {
        let pid = p.id.trimAscii()
        if (pid == id) {
            arr.add(GatewayPluginUserSettings(id: id, enabled: on))
            updated = true
        } else if (!pid.isEmpty()) {
            arr.add(p)
        }
    }
    if (!updated) {
        arr.add(GatewayPluginUserSettings(id: id, enabled: on))
    }
    g.gatewayPlugins = arr.toArray()
    CliSettingManager.writeGatewaySettings(g)
    PrintUtils.printLine("Updated gateway.gatewayPlugins: id=${id}, enabled=${on}")
    true
}

public func gatewayActionsSetPluginField(idRaw: String, keyRaw: String, value: String): Bool {
    let id = idRaw.trimAscii()
    let key = keyRaw.trimAscii()
    if (id.isEmpty() || key.isEmpty()) {
        PrintUtils.printLine("Usage: gateway plugin set <id> <key> <value...>")
        return false
    }
    let installed = gatewayActionsDiscoverInstalledPluginIds()
    if (!installed.contains(id)) {
        PrintUtils.printLine("Installed plugin not found: ${id}")
        return false
    }
    var g = CliSettingManager.readGatewaySettings()
    let root = match (g.channelsExtra) {
        case Some(v) => v
        case None => JsonObject(HashMap<String, JsonValue>())
    }
    let cfg = match (root.get(id)) {
        case Some(v) =>
            try {
                v.asObject()
            } catch (_e: Exception) {
                JsonObject(HashMap<String, JsonValue>())
            }
        case None => JsonObject(HashMap<String, JsonValue>())
    }
    cfg.put(key, JsonString(value))
    root.put(id, cfg)
    g.channelsExtra = Some(root)
    CliSettingManager.writeGatewaySettings(g)
    PrintUtils.printLine("Updated gateway.channelsExtra.${id}.${key}")
    true
}

public func gatewayActionsSetMaster(on: Bool): Unit {
    var g = CliSettingManager.readGatewaySettings()
    g.enabled = on
    CliSettingManager.writeGatewaySettings(g)
    PrintUtils.printLine("gateway.enabled = ${g.enabled}")
}

public func gatewayActionsIsBuiltinChannel(id: String): Bool {
    id == "feishu" || id == "qq"
}

public func gatewayActionsSetChannelEnabled(id: String, on: Bool): Bool {
    if (!gatewayActionsIsBuiltinChannel(id)) {
        PrintUtils.printLine("未知或不可由此命令修改的渠道: ${id}。")
        PrintUtils.printLine("可用: feishu, qq。Telegram 请通过 metis.json 的 gateway.telegram 配置或 Control UI 修改。")
        return false
    }
    var g = CliSettingManager.readGatewaySettings()
    if (id == "feishu") {
        g.feishu.enabled = on
    } else {
        g.qq.enabled = on
    }
    CliSettingManager.writeGatewaySettings(g)
    PrintUtils.printLine("已更新：${id}.enabled = ${on}")
    true
}

public func gatewayActionsSetFeishu(key: String, value: String): Bool {
    var g = CliSettingManager.readGatewaySettings()
    var f = g.feishu
    match (key) {
        case "app-id" => f.appId = value
        case "app-secret" => f.appSecret = value
        case "receive-mode" => f.receiveMode = value
        case "domain" => f.domain = value
        case "bot-open-id" => f.botOpenId = value
        case "webhook-host" => f.webhookHost = value
        case "webhook-path" => f.webhookPath = value
        case "verification-token" => f.verificationToken = value
        case "encrypt-key" => f.encryptKey = value
        case "group-session-scope" =>
            let normalized = value.trimAscii().toAsciiLower()
            if (
                normalized != "group" &&
                normalized != "group_sender" &&
                normalized != "group_topic" &&
                normalized != "group_topic_sender"
            ) {
                PrintUtils.printLine("group-session-scope 仅支持 group | group_sender | group_topic | group_topic_sender")
                return false
            }
            f.groupSessionScope = normalized
        case "reply-in-thread" =>
            let normalized = value.trimAscii().toAsciiLower()
            if (normalized != "enabled" && normalized != "disabled") {
                PrintUtils.printLine("reply-in-thread 仅支持 enabled | disabled")
                return false
            }
            f.replyInThread = normalized
        case "webhook-port" =>
            try {
                f.webhookPort = Int64.parse(value.trimAscii())
            } catch (_e: Exception) {
                PrintUtils.printLine("无效端口: ${value}")
                return false
            }
        case "require-signature-headers" =>
            match (gatewayActionsParseBoolWord(value)) {
                case Some(b) => f.requireSignatureHeaders = b
                case None =>
                    PrintUtils.printLine("需要 true/false: ${value}")
                    return false
            }
        case "max-skew-seconds" =>
            try {
                f.requestMaxSkewSeconds = Int64.parse(value.trimAscii())
            } catch (_e: Exception) {
                PrintUtils.printLine("无效整数: ${value}")
                return false
            }
        case _ =>
            PrintUtils.printLine("未知 feishu 字段: ${key}")
            return false
    }
    g.feishu = f
    CliSettingManager.writeGatewaySettings(g)
    PrintUtils.printLine("已设置 feishu.${key}")
    true
}

public func gatewayActionsSetQq(key: String, value: String): Bool {
    var g = CliSettingManager.readGatewaySettings()
    var q = g.qq
    match (key) {
        case "mode" =>
            if (value.trimAscii().toAsciiLower() != "official_ws") {
                PrintUtils.printLine("QQ currently only supports official_ws mode")
                return false
            }
            q.mode = "official_ws"
        case "app-id" => q.appId = value
        case "app-secret" => q.appSecret = value
        case "bot-qq" => q.botQQ = value
        case "dedup-window-size" =>
            try {
                q.dedupWindowSize = Int64.parse(value.trimAscii())
            } catch (_e: Exception) {
                PrintUtils.printLine("无效整数: ${value}")
                return false
            }
        case "official-intents" =>
            try {
                q.officialIntents = Int64.parse(value.trimAscii())
            } catch (_e: Exception) {
                PrintUtils.printLine("无效整数: ${value}")
                return false
            }
        case "require-auth-header" =>
            match (gatewayActionsParseBoolWord(value)) {
                case Some(b) => q.requireAuthorizationHeader = b
                case None =>
                    PrintUtils.printLine("需要 true/false: ${value}")
                    return false
            }
        case "official-token-url" => q.officialTokenUrl = value
        case "official-gateway-url" => q.officialGatewayUrl = value
        case "official-ws-url" => q.officialWebsocketUrl = value
        case "official-auth-scheme" => q.officialAuthScheme = value
        case "official-send-private-url-template" => q.officialSendPrivateUrlTemplate = value
        case "official-send-group-url-template" => q.officialSendGroupUrlTemplate = value
        case _ =>
            PrintUtils.printLine("未知 qq 字段: ${key}")
            return false
    }
    g.qq = q
    CliSettingManager.writeGatewaySettings(g)
    PrintUtils.printLine("已设置 qq.${key}")
    true
}
