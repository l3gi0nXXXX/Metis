package metis.gateway.config

import metis.core.config.CliConfig
import metis.gateway.channels.plugin.CommandPluginAdapter
import metis.gateway.channels.plugin.LegacyNodePluginAdapter
import metis.gateway.core.ChannelAdapter

import magic.log.LogUtils

import std.collection.{ArrayList, HashMap}
import std.env.getVariable
import std.fs.{Directory, File, Path, exists}

import stdx.encoding.json.{JsonObject, JsonString, JsonValue}

/**
 * 兼容插件模式：扩展渠道以「插件」形式注册到进程内注册表，再由 `gateway.gatewayPlugins` 与 `channelsExtra` 驱动装配。
 * 飞书/QQ 仍由 `gateway_config_factory` 直接接线，不经过本接口。
 */
public interface GatewayChannelPlugin {
    /** 唯一 id，与 metis.json 中 `gateway.gatewayPlugins[].id`、通常也与 `gateway.channelsExtra` 下的配置键一致。 */
    func pluginId(): String

    /**
     * 本插件会占用的 channel 名（与 `ChannelType.Extension(id)`、`ChannelAdapter.name` 一致），用于在创建适配器之前填充路由策略表。
     */
    func declaredChannelIds(): Array<String>

    /** 根据合并后的插件配置创建适配器（可返回空数组表示当前配置下不启用）。 */
    func createAdapters(config: JsonObject): Array<ChannelAdapter>
}

/**
 * 进程内插件注册表（编译期通过 `register` 登记；动态 .dll 加载非本阶段目标）。
 */
public class GatewayChannelPluginRegistry {
    private static var plugins: ArrayList<GatewayChannelPlugin> = ArrayList<GatewayChannelPlugin>()

    public static func register(plugin: GatewayChannelPlugin): Unit {
        let pid = plugin.pluginId()
        let next = ArrayList<GatewayChannelPlugin>()
        for (existing in plugins) {
            if (existing.pluginId() == pid) {
                LogUtils.info("GatewayChannelPluginRegistry: duplicate pluginId '${pid}', replacing")
                continue
            }
            next.add(existing)
        }
        next.add(plugin)
        plugins = next
    }

    public static func getById(id: String): Option<GatewayChannelPlugin> {
        let t = id.trimAscii()
        for (p in plugins) {
            if (p.pluginId() == t) {
                return Some(p)
            }
        }
        None
    }

    public static func allPluginIds(): Array<String> {
        let out = ArrayList<String>()
        for (p in plugins) {
            out.add(p.pluginId())
        }
        out.toArray()
    }
}

private class InstalledCommandGatewayPlugin <: GatewayChannelPlugin {
    private let id: String
    private let channelId: String
    private let root: Path
    private let command: String
    private let script: String

    public init(id: String, channelId: String, root: Path, command: String, script: String) {
        this.id = id
        this.channelId = channelId
        this.root = root
        this.command = command
        this.script = script
    }

    public func pluginId(): String {
        this.id
    }

    public func declaredChannelIds(): Array<String> {
        [this.channelId]
    }

    public func createAdapters(config: JsonObject): Array<ChannelAdapter> {
        let merged = mergePluginConfigWithInstalledDefaults(this.root, config)
        let adapter = CommandPluginAdapter(
            this.id,
            this.channelId,
            this.root,
            this.command,
            this.script,
            merged.toJsonString()
        )
        [adapter]
    }
}

private class InstalledLegacyNodeGatewayPlugin <: GatewayChannelPlugin {
    private let id: String
    private let channelId: String
    private let root: Path
    private let command: String
    private let entry: String
    private let manifestPath: Path

    public init(id: String, channelId: String, root: Path, command: String, entry: String, manifestPath: Path) {
        this.id = id
        this.channelId = channelId
        this.root = root
        this.command = command
        this.entry = entry
        this.manifestPath = manifestPath
    }

    public func pluginId(): String {
        this.id
    }

    public func declaredChannelIds(): Array<String> {
        [this.channelId]
    }

    public func createAdapters(config: JsonObject): Array<ChannelAdapter> {
        let merged = mergePluginConfigWithInstalledDefaults(this.root, config)
        let adapter = LegacyNodePluginAdapter(
            this.id,
            this.channelId,
            this.root,
            this.command,
            this.entry,
            this.manifestPath.toString(),
            merged.toJsonString()
        )
        [adapter]
    }
}

private func defaultLegacyNodeHostEntry(): String {
    let root = match (getVariable("METIS_CJPM_ROOT")) {
        case Some(v) =>
            let trimmed = v.trimAscii()
            if (trimmed.isEmpty()) { CliConfig.cwd.toString() } else { trimmed }
        case None => CliConfig.cwd.toString()
    }
    Path(root).join("scripts").join("legacy-channel-host.mjs").toString()
}

/**
 * 自动发现并注册 `~/.metis/gateway-plugins/xx/` 下的兼容插件 manifest。
 *
 * Manifest 最小约定：
 * {
 *   "id": "dingtalk",
 *   "channels": ["dingtalk"],
 *   "gatewayRuntime": {
 *     "kind": "command-adapter",
 *     "command": "python",
 *     "script": "adapter.py"
 *   }
 * }
 */
public func registerInstalledGatewayPlugins(): Unit {
    let root = CliConfig.dotDir.join("gateway-plugins")
    if (!exists(root)) {
        return
    }
    try {
        for (entry in Directory.readFrom(root)) {
            if (!entry.isDirectory()) {
                continue
            }
            let pluginDir = root.join(entry.name)
            let manifest = pluginDir.join("metis.plugin.json")
            if (!exists(manifest)) {
                continue
            }
            registerInstalledGatewayPluginManifest(pluginDir, manifest)
        }
    } catch (e: Exception) {
        LogUtils.error("Gateway plugin discover failed: ${e.message}")
    }
}

public func ensureInstalledGatewayPluginsRegistered(): Unit {
    registerInstalledGatewayPlugins()
}

private func registerInstalledGatewayPluginManifest(pluginDir: Path, manifestPath: Path): Unit {
    try {
        let raw = String.fromUtf8(File.readFrom(manifestPath))
        let root = JsonValue.fromStr(raw).asObject()
        let id = readManifestString(root, "id")
        if (id.isEmpty()) {
            return
        }
        let channelId = readManifestFirstChannel(root, id)
        let rt = match (root.get("gatewayRuntime")) {
            case Some(v) => v.asObject()
            case None => JsonObject(HashMap<String, JsonValue>())
        }
        let kind = readManifestString(rt, "kind").toAsciiLower()
        if (kind == "command-adapter") {
            let command = readManifestString(rt, "command")
            let script = readManifestString(rt, "script")
            if (command.isEmpty() || script.isEmpty()) {
                LogUtils.info("Gateway plugin '${id}' skipped: command/script missing")
                return
            }
            GatewayChannelPluginRegistry.register(
                InstalledCommandGatewayPlugin(
                    id,
                    channelId,
                    pluginDir,
                    command,
                    script
                )
            )
            return
        }
        if (kind == "legacy-node-plugin" || kind == "legacy-plugin-host") {
            let command = readManifestString(rt, "command")
            let entry = readManifestString(rt, ["hostEntry", "gatewayHostEntry", "entry", "script"])
            let resolvedCommand = if (command.isEmpty()) { "node" } else { command }
            GatewayChannelPluginRegistry.register(
                InstalledLegacyNodeGatewayPlugin(
                    id,
                    channelId,
                    pluginDir,
                    resolvedCommand,
                    if (entry.isEmpty()) { defaultLegacyNodeHostEntry() } else { entry },
                    manifestPath
                )
            )
            return
        }
        LogUtils.info("Gateway plugin '${id}' skipped: unsupported gatewayRuntime.kind='${kind}'")
    } catch (e: Exception) {
        LogUtils.error("Gateway plugin manifest parse failed (${manifestPath.toString()}): ${e.message}")
    }
}

private func readManifestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try {
                v.asString().getValue().trimAscii()
            } catch (_e: Exception) {
                ""
            }
        case None => ""
    }
}

private func readManifestString(obj: JsonObject, keys: Array<String>): String {
    for (key in keys) {
        let value = readManifestString(obj, key)
        if (!value.isEmpty()) {
            return value
        }
    }
    ""
}

private func readManifestFirstChannel(obj: JsonObject, fallback: String): String {
    match (obj.get("channels")) {
        case Some(v) =>
            try {
                let arr = v.asArray()
                if (arr.size() > 0) {
                    let s = arr[0].asString().getValue().trimAscii()
                    if (!s.isEmpty()) {
                        return s
                    }
                }
                fallback
            } catch (_e: Exception) {
                fallback
            }
        case None => fallback
    }
}

/**
 * 合并配置优先级：metis.json gateway.channelsExtra.<id> > plugin-config.json
 */
private func mergePluginConfigWithInstalledDefaults(pluginDir: Path, runtimeCfg: JsonObject): JsonObject {
    // 当前 JsonObject 在本仓库依赖版本下不支持直接 keys()/for-in 迭代，
    // 这里采用稳定策略：runtimeCfg 非空则直接使用；否则回退到安装时的 plugin-config.json。
    let t = runtimeCfg.toJsonString().trimAscii()
    if (!t.isEmpty() && t != "{}") {
        return runtimeCfg
    }
    readInstalledPluginConfig(pluginDir)
}

private func readInstalledPluginConfig(pluginDir: Path): JsonObject {
    let p = pluginDir.join("plugin-config.json")
    if (!exists(p)) {
        return JsonObject(HashMap<String, JsonValue>())
    }
    try {
        let raw = String.fromUtf8(File.readFrom(p))
        JsonValue.fromStr(raw).asObject()
    } catch (_e: Exception) {
        JsonObject(HashMap<String, JsonValue>())
    }
}

/** 从 `gateway.channelsExtra` 根对象下读取 `pluginId` 键对应的 JSON 对象作为插件配置。 */
public func pluginConfigFromChannelsExtra(extra: Option<JsonObject>, pluginId: String): JsonObject {
    let key = pluginId.trimAscii()
    match (extra) {
        case Some(root) =>
            match (root.get(key)) {
                case Some(v) => v.asObject()
                case None => JsonObject(HashMap<String, JsonValue>())
            }
        case None => JsonObject(HashMap<String, JsonValue>())
    }
}

public func pluginConfigFromChannelsExtraObject(extra: Option<JsonObject>, pluginId: String): JsonObject {
    pluginConfigFromChannelsExtra(extra, pluginId)
}

public func gatewayPluginConfigPresent(extra: Option<JsonObject>, pluginId: String): Bool {
    pluginConfigFromChannelsExtra(extra, pluginId).toJsonString().trimAscii() != "{}"
}
