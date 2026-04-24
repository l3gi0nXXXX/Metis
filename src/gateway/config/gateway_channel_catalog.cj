package metis.gateway.config

import metis.core.config.CliConfig
import magic.jsonable.*

import std.collection.ArrayList
import std.convert.Parsable
import std.fs.{Directory, File, Path, exists}

import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

public class GatewayPluginCatalogEntry {
    public let id: String
    public let label: String
    public let detailLabel: String
    public let systemImage: String
    public let origin: String
    public let docsUrl: String
    public let order: Int64
    public let installed: Bool
    public let registered: Bool
    public let builtin: Bool
    public let setupSupported: Bool
    public let channelIds: Array<String>
    public let runtimeKind: String
    public let compatibilityMode: String

    public init(
        id: String,
        label!: String = "",
        detailLabel!: String = "",
        systemImage!: String = "",
        origin!: String = "installed",
        docsUrl!: String = "",
        order!: Int64 = 1000,
        installed!: Bool = false,
        registered!: Bool = false,
        builtin!: Bool = false,
        setupSupported!: Bool = false,
        channelIds!: Array<String> = [],
        runtimeKind!: String = "native",
        compatibilityMode!: String = "native-cangjie"
    ) {
        this.id = id.trimAscii().toAsciiLower()
        this.label = if (label.trimAscii().isEmpty()) { this.id } else { label.trimAscii() }
        this.detailLabel = detailLabel.trimAscii()
        this.systemImage = systemImage.trimAscii()
        this.origin = origin.trimAscii()
        this.docsUrl = docsUrl.trimAscii()
        this.order = order
        this.installed = installed
        this.registered = registered
        this.builtin = builtin
        this.setupSupported = setupSupported
        this.channelIds = channelIds
        this.runtimeKind = runtimeKind.trimAscii()
        this.compatibilityMode = compatibilityMode.trimAscii()
    }

    public func toJson(): JsonObject {
        let obj = JsonObject()
        obj.put("id", JsonString(this.id))
        obj.put("label", JsonString(this.label))
        obj.put("detailLabel", JsonString(this.detailLabel))
        obj.put("systemImage", JsonString(this.systemImage))
        obj.put("origin", JsonString(this.origin))
        obj.put("docsUrl", JsonString(this.docsUrl))
        obj.put("order", this.order.toJsonValue())
        obj.put("installed", this.installed.toJsonValue())
        obj.put("registered", this.registered.toJsonValue())
        obj.put("builtin", this.builtin.toJsonValue())
        obj.put("setupSupported", this.setupSupported.toJsonValue())
        obj.put("channelIds", this.channelIds.toJsonValue())
        obj.put("runtimeKind", JsonString(this.runtimeKind))
        obj.put("compatibilityMode", JsonString(this.compatibilityMode))
        obj
    }
}

public class GatewayChannelCatalogEntry {
    public let id: String
    public let label: String
    public let detailLabel: String
    public let systemImage: String
    public let origin: String
    public let docsUrl: String
    public let pluginId: String
    public let pluginLabel: String
    public let order: Int64
    public let builtin: Bool
    public let installed: Bool
    public let registered: Bool
    public let setupSupported: Bool

    public init(
        id: String,
        label!: String = "",
        detailLabel!: String = "",
        systemImage!: String = "",
        origin!: String = "installed",
        docsUrl!: String = "",
        pluginId!: String = "",
        pluginLabel!: String = "",
        order!: Int64 = 1000,
        builtin!: Bool = false,
        installed!: Bool = false,
        registered!: Bool = false,
        setupSupported!: Bool = false
    ) {
        this.id = id.trimAscii().toAsciiLower()
        this.label = if (label.trimAscii().isEmpty()) { this.id } else { label.trimAscii() }
        this.detailLabel = detailLabel.trimAscii()
        this.systemImage = systemImage.trimAscii()
        this.origin = origin.trimAscii()
        this.docsUrl = docsUrl.trimAscii()
        this.pluginId = pluginId.trimAscii().toAsciiLower()
        this.pluginLabel = pluginLabel.trimAscii()
        this.order = order
        this.builtin = builtin
        this.installed = installed
        this.registered = registered
        this.setupSupported = setupSupported
    }

    public func toJson(): JsonObject {
        let obj = JsonObject()
        obj.put("id", JsonString(this.id))
        obj.put("label", JsonString(this.label))
        obj.put("detailLabel", JsonString(this.detailLabel))
        obj.put("systemImage", JsonString(this.systemImage))
        obj.put("origin", JsonString(this.origin))
        obj.put("docsUrl", JsonString(this.docsUrl))
        obj.put("pluginId", JsonString(this.pluginId))
        obj.put("pluginLabel", JsonString(this.pluginLabel))
        obj.put("order", this.order.toJsonValue())
        obj.put("builtin", this.builtin.toJsonValue())
        obj.put("installed", this.installed.toJsonValue())
        obj.put("registered", this.registered.toJsonValue())
        obj.put("setupSupported", this.setupSupported.toJsonValue())
        obj
    }
}

private let GATEWAY_BUILTIN_CHANNEL_ORDER = ["feishu", "qq", "telegram", "slack", "discord"]

public func normalizeGatewayChannelId(raw: String): String {
    raw.trimAscii().toAsciiLower()
}

private func gatewayBuiltinPluginCatalogEntries(): Array<GatewayPluginCatalogEntry> {
    [
        GatewayPluginCatalogEntry(
            "feishu",
            label: "Feishu",
            detailLabel: "Built-in Feishu adapter",
            systemImage: "message.fill",
            origin: "builtin",
            order: 10,
            installed: true,
            registered: true,
            builtin: true,
            setupSupported: true,
            channelIds: ["feishu"],
            runtimeKind: "builtin-adapter",
            compatibilityMode: "native-cangjie"
        ),
        GatewayPluginCatalogEntry(
            "qq",
            label: "QQ",
            detailLabel: "Built-in QQ adapter",
            systemImage: "bubble.left.and.bubble.right.fill",
            origin: "builtin",
            order: 20,
            installed: true,
            registered: true,
            builtin: true,
            setupSupported: true,
            channelIds: ["qq"],
            runtimeKind: "builtin-adapter",
            compatibilityMode: "native-cangjie"
        ),
        GatewayPluginCatalogEntry(
            "telegram",
            label: "Telegram",
            detailLabel: "Built-in Telegram adapter",
            systemImage: "paperplane.fill",
            origin: "builtin",
            docsUrl: "https://core.telegram.org/bots",
            order: 30,
            installed: true,
            registered: true,
            builtin: true,
            setupSupported: true,
            channelIds: ["telegram"],
            runtimeKind: "builtin-adapter",
            compatibilityMode: "native-cangjie"
        ),
        GatewayPluginCatalogEntry(
            "slack",
            label: "Slack",
            detailLabel: "Built-in Slack adapter",
            systemImage: "number.square.fill",
            origin: "builtin",
            docsUrl: "https://api.slack.com",
            order: 40,
            installed: true,
            registered: true,
            builtin: true,
            setupSupported: true,
            channelIds: ["slack"],
            runtimeKind: "builtin-adapter",
            compatibilityMode: "native-cangjie"
        ),
        GatewayPluginCatalogEntry(
            "discord",
            label: "Discord",
            detailLabel: "Built-in Discord adapter",
            systemImage: "gamecontroller.fill",
            origin: "builtin",
            docsUrl: "https://discord.com/developers/docs",
            order: 50,
            installed: true,
            registered: true,
            builtin: true,
            setupSupported: true,
            channelIds: ["discord"],
            runtimeKind: "builtin-adapter",
            compatibilityMode: "native-cangjie"
        )
    ]
}

private func readCatalogString(obj: JsonObject, keys: Array<String>, defaultValue!: String = ""): String {
    for (key in keys) {
        match (obj.get(key)) {
            case Some(v) =>
                try {
                    let value = v.asString().getValue().trimAscii()
                    if (!value.isEmpty()) {
                        return value
                    }
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
    }
    defaultValue
}

private func readCatalogInt(obj: JsonObject, keys: Array<String>, defaultValue!: Int64 = 1000): Int64 {
    for (key in keys) {
        match (obj.get(key)) {
            case Some(v) =>
                try {
                    return Int64.parse(v.toJsonString())
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
    }
    defaultValue
}

private func readCatalogBool(obj: JsonObject, keys: Array<String>, defaultValue!: Bool = false): Bool {
    for (key in keys) {
        match (obj.get(key)) {
            case Some(v) =>
                try {
                    return v.asBool().getValue()
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
    }
    defaultValue
}

private func readCatalogChannels(obj: JsonObject, fallback: String): Array<String> {
    let out = ArrayList<String>()
    match (obj.get("channels")) {
        case Some(v) =>
            try {
                let arr = v.asArray()
                for (i in 0..arr.size()) {
                    let channelId = normalizeGatewayChannelId(arr[i].asString().getValue())
                    if (!channelId.isEmpty() && !out.contains(channelId)) {
                        out.add(channelId)
                    }
                }
            } catch (_e: Exception) {
                ()
            }
        case None => ()
    }
    if (out.isEmpty() && !fallback.trimAscii().isEmpty()) {
        out.add(normalizeGatewayChannelId(fallback))
    }
    out.toArray()
}

private func gatewayCatalogInsertByOrder(entries: ArrayList<GatewayPluginCatalogEntry>, entry: GatewayPluginCatalogEntry): Unit {
    entries.add(entry)
}

private func gatewayCatalogRoot(): Path {
    CliConfig.dotDir.join("gateway-plugins")
}

private func gatewayManifestPath(dir: Path): Path {
    dir.join("metis.plugin.json")
}

private func gatewayReadPluginCatalogEntry(pluginDir: Path): Option<GatewayPluginCatalogEntry> {
    let manifestPath = gatewayManifestPath(pluginDir)
    if (!exists(manifestPath)) {
        return None<GatewayPluginCatalogEntry>
    }
    try {
        let root = JsonValue.fromStr(String.fromUtf8(File.readFrom(manifestPath))).asObject()
        let pluginId = normalizeGatewayChannelId(readCatalogString(root, ["id"]))
        if (pluginId.isEmpty()) {
            return None<GatewayPluginCatalogEntry>
        }
        if (GATEWAY_BUILTIN_CHANNEL_ORDER.contains(pluginId)) {
            return None<GatewayPluginCatalogEntry>
        }
        let channelIds = readCatalogChannels(root, pluginId)
        let label = readCatalogString(root, ["label", "name"], defaultValue: pluginId)
        let detailLabel = readCatalogString(root, ["detailLabel", "description"], defaultValue: "Installed gateway plugin")
        let systemImage = readCatalogString(root, ["systemImage"], defaultValue: "puzzlepiece.extension.fill")
        let docsUrl = readCatalogString(root, ["docsUrl", "docs", "homepage"])
        let order = readCatalogInt(root, ["order"], defaultValue: 1000)
        let runtime = match (root.get("gatewayRuntime")) {
            case Some(v) =>
                try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let runtimeKind = readCatalogString(runtime, ["kind"], defaultValue: "unknown")
        let compatibilityMode = if (runtimeKind == "legacy-node-plugin" || runtimeKind == "legacy-plugin-host") {
            "legacy-plugin-host"
        } else if (runtimeKind == "command-adapter") {
            "command-adapter"
        } else {
            "installed-manifest"
        }
        let setupSupported = readCatalogBool(root, ["setupSupported", "setup"], defaultValue: false) || match (root.get("gatewaySetup")) {
            case Some(_) => true
            case None => false
        }
        let registered = match (GatewayChannelPluginRegistry.getById(pluginId)) {
            case Some(_) => true
            case None => false
        }
        return Some(
            GatewayPluginCatalogEntry(
                pluginId,
                label: label,
                detailLabel: detailLabel,
                systemImage: systemImage,
                origin: "installed",
                docsUrl: docsUrl,
                order: order,
                installed: true,
                registered: registered,
                builtin: false,
                setupSupported: setupSupported,
                channelIds: channelIds,
                runtimeKind: runtimeKind,
                compatibilityMode: compatibilityMode
            )
        )
    } catch (_e: Exception) {
        None<GatewayPluginCatalogEntry>
    }
}

public func listGatewayPluginCatalogEntries(): Array<GatewayPluginCatalogEntry> {
    let entries = ArrayList<GatewayPluginCatalogEntry>()
    let seen = ArrayList<String>()
    for (builtin in gatewayBuiltinPluginCatalogEntries()) {
        seen.add(builtin.id)
        gatewayCatalogInsertByOrder(entries, builtin)
    }
    let root = gatewayCatalogRoot()
    if (exists(root)) {
        try {
            for (entry in Directory.readFrom(root)) {
                if (!entry.isDirectory()) {
                    continue
                }
                match (gatewayReadPluginCatalogEntry(root.join(entry.name))) {
                    case Some(pluginEntry) =>
                        if (!seen.contains(pluginEntry.id)) {
                            seen.add(pluginEntry.id)
                            gatewayCatalogInsertByOrder(entries, pluginEntry)
                        }
                    case None => ()
                }
            }
        } catch (_e: Exception) {
            ()
        }
    }
    for (pluginId in GatewayChannelPluginRegistry.allPluginIds()) {
        let normalized = normalizeGatewayChannelId(pluginId)
        if (normalized.isEmpty() || seen.contains(normalized)) {
            continue
        }
        seen.add(normalized)
        gatewayCatalogInsertByOrder(
            entries,
            GatewayPluginCatalogEntry(
                normalized,
                label: normalized,
                detailLabel: "Registered gateway plugin",
                systemImage: "puzzlepiece.extension.fill",
                origin: "registered",
                order: 1000,
                installed: false,
                registered: true,
                builtin: false,
                setupSupported: false,
                channelIds: [normalized],
                runtimeKind: "registered-plugin",
                compatibilityMode: "native-cangjie"
            )
        )
    }
    entries.toArray()
}

public func getGatewayPluginCatalogEntry(pluginId: String): Option<GatewayPluginCatalogEntry> {
    let normalized = normalizeGatewayChannelId(pluginId)
    for (entry in listGatewayPluginCatalogEntries()) {
        if (entry.id == normalized) {
            return Some(entry)
        }
    }
    None<GatewayPluginCatalogEntry>
}

public func listGatewayChannelCatalogEntries(): Array<GatewayChannelCatalogEntry> {
    let out = ArrayList<GatewayChannelCatalogEntry>()
    let seen = ArrayList<String>()
    for (pluginEntry in listGatewayPluginCatalogEntries()) {
        for (channelId in pluginEntry.channelIds) {
            let normalized = normalizeGatewayChannelId(channelId)
            if (normalized.isEmpty() || seen.contains(normalized)) {
                continue
            }
            seen.add(normalized)
            out.add(
                GatewayChannelCatalogEntry(
                    normalized,
                    label: if (pluginEntry.builtin) {
                        if (normalized == "feishu") { "Feishu" } else if (normalized == "qq") { "QQ" } else { pluginEntry.label }
                    } else {
                        pluginEntry.label
                    },
                    detailLabel: pluginEntry.detailLabel,
                    systemImage: pluginEntry.systemImage,
                    origin: pluginEntry.origin,
                    docsUrl: pluginEntry.docsUrl,
                    pluginId: pluginEntry.id,
                    pluginLabel: pluginEntry.label,
                    order: pluginEntry.order,
                    builtin: pluginEntry.builtin,
                    installed: pluginEntry.installed,
                    registered: pluginEntry.registered,
                    setupSupported: pluginEntry.setupSupported
                )
            )
        }
    }
    out.toArray()
}

public func getGatewayChannelCatalogEntry(channelId: String): Option<GatewayChannelCatalogEntry> {
    let normalized = normalizeGatewayChannelId(channelId)
    for (entry in listGatewayChannelCatalogEntries()) {
        if (entry.id == normalized) {
            return Some(entry)
        }
    }
    None<GatewayChannelCatalogEntry>
}

public func gatewayPluginCatalogJson(): JsonArray {
    let arr = JsonArray([])
    for (entry in listGatewayPluginCatalogEntries()) {
        arr.add(entry.toJson())
    }
    arr
}

public func gatewayChannelCatalogJson(): JsonArray {
    let arr = JsonArray([])
    for (entry in listGatewayChannelCatalogEntries()) {
        arr.add(entry.toJson())
    }
    arr
}
