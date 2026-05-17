package metis.gateway.runtime

import metis.core.config.{GatewayUserSettings, MetisConfigManager, MetisConfigWriteNotification}

import magic.log.LogUtils

import std.collection.{ArrayList, HashSet}
import std.fs.{File, Path, exists}
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonObject, JsonValue}

public class GatewayConfigSnapshot {
    public let exists: Bool
    public let valid: Bool
    public let root: JsonObject
    public let hash: String
    public let error: String

    public init(
        exists: Bool,
        valid: Bool,
        root!: JsonObject = JsonObject(),
        hash!: String = "",
        error!: String = ""
    ) {
        this.exists = exists
        this.valid = valid
        this.root = root
        this.hash = hash.trimAscii()
        this.error = error.trimAscii()
    }
}

private func gatewayConfigReloadNowMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toMilliseconds()
}

public func gatewayConfigStableHash(text: String): String {
    var hash: Int64 = 5381
    for (b in text.toArray()) {
        hash = ((hash << 5) + hash) + Int64(b)
    }
    if (hash < 0) {
        hash = -hash
    }
    hash.toString()
}

private func gatewayConfigValueIsObject(value: JsonValue): Bool {
    try {
        let _ = value.asObject()
        true
    } catch (_e: Exception) {
        false
    }
}

private func gatewayConfigValueIsArray(value: JsonValue): Bool {
    try {
        let _ = value.asArray()
        true
    } catch (_e: Exception) {
        false
    }
}

private func gatewayConfigDiffValues(prev: JsonValue, next: JsonValue, prefix: String, out: ArrayList<String>): Unit {
    if (prev.toJsonString() == next.toJsonString()) {
        return
    }
    if (gatewayConfigValueIsObject(prev) && gatewayConfigValueIsObject(next)) {
        let prevObj = prev.asObject()
        let nextObj = next.asObject()
        let keys = HashSet<String>()
        for (key in prevObj.getFields().keys()) {
            keys.add(key)
        }
        for (key in nextObj.getFields().keys()) {
            keys.add(key)
        }
        for (key in keys) {
            let childPrefix = if (prefix.isEmpty()) { key } else { "${prefix}.${key}" }
            match (prevObj.get(key)) {
                case Some(prevChild) =>
                    match (nextObj.get(key)) {
                        case Some(nextChild) => gatewayConfigDiffValues(prevChild, nextChild, childPrefix, out)
                        case None => out.add(childPrefix)
                    }
                case None =>
                    match (nextObj.get(key)) {
                        case Some(_) => out.add(childPrefix)
                        case None => ()
                    }
            }
        }
        return
    }
    if (gatewayConfigValueIsArray(prev) && gatewayConfigValueIsArray(next)) {
        if (prev.asArray().toJsonString() == next.asArray().toJsonString()) {
            return
        }
    }
    out.add(if (prefix.isEmpty()) { "<root>" } else { prefix })
}

public func diffGatewayConfigPaths(prev: JsonObject, next: JsonObject): Array<String> {
    let out = ArrayList<String>()
    gatewayConfigDiffValues(prev, next, "", out)
    out.toArray()
}

public func readGatewayConfigSnapshot(path!: Path = MetisConfigManager.configPath()): GatewayConfigSnapshot {
    if (!exists(path)) {
        return GatewayConfigSnapshot(false, false, error: "config file not found")
    }
    try {
        let text = String.fromUtf8(File.readFrom(path))
        GatewayConfigSnapshot(
            true,
            true,
            root: JsonValue.fromStr(text).asObject(),
            hash: gatewayConfigStableHash(text)
        )
    } catch (e: Exception) {
        GatewayConfigSnapshot(true, false, error: e.message)
    }
}

private func gatewayReloadMode(raw: String): String {
    let mode = raw.trimAscii().toAsciiLower()
    if (mode == "off" || mode == "hot" || mode == "restart" || mode == "hybrid") {
        return mode
    }
    "hybrid"
}

private func gatewayReloadDebounceMs(raw: Int64): Int64 {
    if (raw < 0) { 0 } else { raw }
}

public interface GatewayConfigReloadCallbacks {
    func onHotReload(plan: GatewayReloadPlan, nextUser: GatewayUserSettings): Unit
    func onRestartRequired(plan: GatewayReloadPlan, nextUser: GatewayUserSettings): Unit
}

public class GatewayConfigReloader {
    private var currentRoot: JsonObject
    private var currentHash: String
    private var pendingRoot: Option<JsonObject> = None<JsonObject>
    private var pendingHash: String = ""
    private var pendingAtMs: Int64 = 0
    private var stopped: Bool = false
    private let callbacks: GatewayConfigReloadCallbacks

    public init(initialRoot: JsonObject, callbacks: GatewayConfigReloadCallbacks) {
        this.currentRoot = initialRoot
        this.currentHash = gatewayConfigStableHash(initialRoot.toJsonString())
        this.callbacks = callbacks
        MetisConfigManager.setWriteRootNotificationHook(Some<(MetisConfigWriteNotification) -> Unit>(
            { event: MetisConfigWriteNotification =>
                if (event.configPath == MetisConfigManager.configPath().toString()) {
                    this.queueSnapshot(event.runtimeRoot, event.persistedHash)
                }
            }
        ))
    }

    public func stop(): Unit {
        this.stopped = true
        MetisConfigManager.setWriteRootNotificationHook(None<(MetisConfigWriteNotification) -> Unit>)
    }

    public func queueSnapshot(root: JsonObject, hash: String): Unit {
        if (this.stopped) {
            return
        }
        this.pendingRoot = Some(root)
        this.pendingHash = if (hash.trimAscii().isEmpty()) {
            gatewayConfigStableHash(root.toJsonString())
        } else {
            hash.trimAscii()
        }
        this.pendingAtMs = gatewayConfigReloadNowMs()
    }

    public func pollOnce(): Unit {
        if (this.stopped) {
            return
        }
        match (this.pendingRoot) {
            case Some(root) =>
                let user = gatewayUserSettingsFromRoot(root)
                if (gatewayConfigReloadNowMs() - this.pendingAtMs < gatewayReloadDebounceMs(user.reload.debounceMs)) {
                    return
                }
                this.pendingRoot = None<JsonObject>
                this.applyRoot(root, user, this.pendingHash)
            case None =>
                let snapshot = readGatewayConfigSnapshot()
                if (!snapshot.exists) {
                    return
                }
                if (!snapshot.valid) {
                    LogUtils.error("Gateway.config.reload: invalid config snapshot skipped: ${snapshot.error}")
                    return
                }
                if (snapshot.hash == this.currentHash) {
                    return
                }
                this.queueSnapshot(snapshot.root, snapshot.hash)
        }
    }

    private func applyRoot(root: JsonObject, user: GatewayUserSettings, hash: String): Unit {
        let changedPaths = diffGatewayConfigPaths(this.currentRoot, root)
        this.currentRoot = root
        this.currentHash = if (hash.trimAscii().isEmpty()) { gatewayConfigStableHash(root.toJsonString()) } else { hash.trimAscii() }
        if (changedPaths.size == 0) {
            return
        }
        let plan = buildGatewayReloadPlan(changedPaths)
        let mode = gatewayReloadMode(user.reload.mode)
        if (mode == "off") {
            LogUtils.info("Gateway.config.reload: skipped because gateway.reload.mode=off")
            return
        }
        if (mode == "restart") {
            this.callbacks.onRestartRequired(plan, user)
            return
        }
        if (plan.restartGateway) {
            if (mode == "hot") {
                LogUtils.error("Gateway.config.reload: hot mode cannot apply restart-required config change")
                return
            }
            this.callbacks.onRestartRequired(plan, user)
            return
        }
        this.callbacks.onHotReload(plan, user)
    }
}

public func gatewayUserSettingsFromRoot(root: JsonObject): GatewayUserSettings {
    match (root.get("gateway")) {
        case Some(value) =>
            try {
                GatewayUserSettings.fromJsonValue(value)
            } catch (_e: Exception) {
                GatewayUserSettings()
            }
        case None => GatewayUserSettings()
    }
}
