package metis.core.config

import magic.config.Config
import magic.jsonable.*
import magic.log.LogUtils

import std.fs.{File, exists, Path}
import std.collection.{filter, collectArray, ArrayList}
import std.convert.Parsable
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonBool, JsonFloat, JsonInt, JsonValue, JsonObject, JsonString}

public class MetisConfigWriteNotification {
    public let configPath: String
    public let runtimeRoot: JsonObject
    public let persistedHash: String
    public let writtenAtMs: Int64

    public init(configPath: String, runtimeRoot: JsonObject, persistedHash: String, writtenAtMs: Int64) {
        this.configPath = configPath.trimAscii()
        this.runtimeRoot = runtimeRoot
        this.persistedHash = persistedHash.trimAscii()
        this.writtenAtMs = writtenAtMs
    }
}

private func metisConfigStableHash(text: String): String {
    var hash: Int64 = 5381
    for (b in text.toArray()) {
        hash = ((hash << 5) + hash) + Int64(b)
    }
    if (hash < 0) {
        hash = -hash
    }
    hash.toString()
}

private func loadJsonFileWithoutComments(path: Path): String {
    String.join(
        String.fromUtf8(File.readFrom(path)).split("\n") |>
            filter { line => !line.trimAscii().startsWith("//") } |>
            collectArray,
        delimiter: "\n"
    )
}

private func legacySettingsPath(): Path {
    Path(".").join(".magic-cli").join("settings.json")
}

private func cfgGetObject(root: JsonObject, key: String): Option<JsonObject> {
    match (root.get(key)) {
        case Some(value) =>
            try {
                value.asObject()
            } catch (_: Exception) {
                None
            }
        case None => None
    }
}

private func cfgGetString(root: JsonObject, key: String): Option<String> {
    match (root.get(key)) {
        case Some(value) =>
            try {
                Some(value.asString().getValue())
            } catch (_: Exception) {
                None
            }
        case None => None
    }
}

private func cfgGetBool(root: JsonObject, key: String): Option<Bool> {
    match (root.get(key)) {
        case Some(value) =>
            try {
                Some(value.asBool().getValue())
            } catch (_: Exception) {
                None
            }
        case None => None
    }
}

private func cfgGetStringArray(root: JsonObject, key: String): Option<Array<String>> {
    match (root.get(key)) {
        case Some(value) =>
            try {
                let arr = value.asArray()
                let out = ArrayList<String>()
                for (item in arr.getItems()) {
                    try {
                        let text = item.asString().getValue().trimAscii()
                        if (!text.isEmpty()) {
                            out.add(text)
                        }
                    } catch (_: Exception) {
                        ()
                    }
                }
                Some(out.toArray())
            } catch (_: Exception) {
                None
            }
        case None => None
    }
}

private func cfgCopyScalar(root: JsonObject, key: String, projected: JsonObject): Unit {
    match (root.get(key)) {
        case Some(value) =>
            match (value) {
                case v: JsonBool =>
                    projected.put(key, v)
                case v: JsonInt =>
                    projected.put(key, v)
                case v: JsonFloat =>
                    projected.put(key, v)
                case _ => ()
            }
        case None => ()
    }
}

private func normalizeAgentConfigId(raw: String): String {
    raw.trimAscii().toAsciiLower()
}

private func resolveAgentSkillsOverride(entry: JsonObject): Option<Array<String>> {
    match (entry.get("skills")) {
        case Some(value) =>
            try {
                let arr = value.asArray()
                let out = ArrayList<String>()
                for (item in arr.getItems()) {
                    try {
                        let text = item.asString().getValue().trimAscii()
                        if (!text.isEmpty()) {
                            out.add(text)
                        }
                    } catch (_e: Exception) {
                        ()
                    }
                }
                Some(out.toArray())
            } catch (_e: Exception) {
                // Follow the upstream explicit replacement intent: once `skills` is present on the
                // agent entry, it overrides defaults even if malformed, so fail closed.
                Some(Array<String>())
            }
        case None => None
    }
}

private func projectMemorySearchConfig(obj: JsonObject): Option<JsonObject> {
    let projected = JsonObject()
    match (cfgGetString(obj, "provider")) {
        case Some(provider) =>
            let normalized = provider.trimAscii()
            if (!normalized.isEmpty()) {
                projected.put("provider", JsonString(normalized))
            }
        case None => ()
    }
    match (cfgGetBool(obj, "enabled")) {
        case Some(enabled) => projected.put("enabled", enabled.toJsonValue())
        case None => ()
    }
    match (cfgGetString(obj, "model")) {
        case Some(model) =>
            let normalized = model.trimAscii()
            if (!normalized.isEmpty()) {
                projected.put("model", JsonString(normalized))
            }
        case None => ()
    }
    cfgCopyScalar(obj, "outputDimensionality", projected)
    match (obj.get("fallback")) {
        case Some(value) =>
            try {
                projected.put("fallback", JsonString(value.asString().getValue().trimAscii()))
            } catch (_: Exception) {
                ()
            }
        case None => ()
    }
    match (cfgGetStringArray(obj, "extraPaths")) {
        case Some(paths) =>
            let arr = JsonArray([])
            for (path in paths) {
                arr.add(JsonString(path))
            }
            projected.put("extraPaths", arr)
        case None => ()
    }
    match (cfgGetObject(obj, "qmd")) {
        case Some(qmdRaw) =>
            let qmdProjected = JsonObject()
            match (cfgGetStringArray(qmdRaw, "extraCollections")) {
                case Some(collections) =>
                    let arr = JsonArray([])
                    for (collection in collections) {
                        arr.add(JsonString(collection))
                    }
                    qmdProjected.put("extraCollections", arr)
                case None => ()
            }
            if (qmdProjected.toJsonString() != "{}") {
                projected.put("qmd", qmdProjected)
            }
        case None => ()
    }
    match (cfgGetObject(obj, "remote")) {
        case Some(remoteRaw) =>
            let remoteProjected = JsonObject()
            match (cfgGetString(remoteRaw, "baseUrl")) {
                case Some(baseUrl) =>
                    let normalized = baseUrl.trimAscii()
                    if (!normalized.isEmpty()) {
                        remoteProjected.put("baseUrl", JsonString(normalized))
                    }
                case None => ()
            }
            match (cfgGetString(remoteRaw, "apiKey")) {
                case Some(apiKey) =>
                    let normalized = apiKey.trimAscii()
                    if (!normalized.isEmpty()) {
                        remoteProjected.put("apiKey", JsonString(normalized))
                    }
                case None => ()
            }
            match (remoteRaw.get("headers")) {
                case Some(headersValue) =>
                    try {
                        remoteProjected.put("headers", headersValue.asObject())
                    } catch (_: Exception) {
                        ()
                    }
                case None => ()
            }
            if (remoteProjected.toJsonString() != "{}") {
                projected.put("remote", remoteProjected)
            }
        case None => ()
    }
    match (cfgGetObject(obj, "local")) {
        case Some(localRaw) =>
            let localProjected = JsonObject()
            match (cfgGetString(localRaw, "modelPath")) {
                case Some(modelPath) =>
                    let normalized = modelPath.trimAscii()
                    if (!normalized.isEmpty()) {
                        localProjected.put("modelPath", JsonString(normalized))
                    }
                case None => ()
            }
            match (cfgGetString(localRaw, "modelCacheDir")) {
                case Some(modelCacheDir) =>
                    let normalized = modelCacheDir.trimAscii()
                    if (!normalized.isEmpty()) {
                        localProjected.put("modelCacheDir", JsonString(normalized))
                    }
                case None => ()
            }
            if (localProjected.toJsonString() != "{}") {
                projected.put("local", localProjected)
            }
        case None => ()
    }
    match (cfgGetObject(obj, "query")) {
        case Some(queryRaw) =>
            match (cfgGetObject(queryRaw, "hybrid")) {
                case Some(hybridRaw) =>
                    let hybridProjected = JsonObject()
                    cfgCopyScalar(hybridRaw, "enabled", hybridProjected)
                    cfgCopyScalar(hybridRaw, "vectorWeight", hybridProjected)
                    cfgCopyScalar(hybridRaw, "textWeight", hybridProjected)
                    cfgCopyScalar(hybridRaw, "candidateMultiplier", hybridProjected)
                    match (cfgGetObject(hybridRaw, "mmr")) {
                        case Some(mmrRaw) =>
                            let mmrProjected = JsonObject()
                            cfgCopyScalar(mmrRaw, "enabled", mmrProjected)
                            cfgCopyScalar(mmrRaw, "lambda", mmrProjected)
                            if (mmrProjected.toJsonString() != "{}") {
                                hybridProjected.put("mmr", mmrProjected)
                            }
                        case None => ()
                    }
                    match (cfgGetObject(hybridRaw, "temporalDecay")) {
                        case Some(decayRaw) =>
                            let decayProjected = JsonObject()
                            cfgCopyScalar(decayRaw, "enabled", decayProjected)
                            cfgCopyScalar(decayRaw, "halfLifeDays", decayProjected)
                            if (decayProjected.toJsonString() != "{}") {
                                hybridProjected.put("temporalDecay", decayProjected)
                            }
                        case None => ()
                    }
                    if (hybridProjected.toJsonString() != "{}") {
                        let queryProjected = JsonObject()
                        queryProjected.put("hybrid", hybridProjected)
                        projected.put("query", queryProjected)
                    }
                case None => ()
            }
        case None => ()
    }
    match (cfgGetObject(obj, "store")) {
        case Some(storeRaw) =>
            let storeProjected = JsonObject()
            match (cfgGetString(storeRaw, "driver")) {
                case Some(driver) =>
                    let normalized = driver.trimAscii()
                    if (!normalized.isEmpty()) {
                        storeProjected.put("driver", JsonString(normalized))
                    }
                case None => ()
            }
            match (cfgGetString(storeRaw, "path")) {
                case Some(path) =>
                    let normalized = path.trimAscii()
                    if (!normalized.isEmpty()) {
                        storeProjected.put("path", JsonString(normalized))
                    }
                case None => ()
            }
            match (cfgGetObject(storeRaw, "fts")) {
                case Some(ftsRaw) =>
                    let ftsProjected = JsonObject()
                    match (cfgGetString(ftsRaw, "tokenizer")) {
                        case Some(tokenizer) =>
                            let normalized = tokenizer.trimAscii()
                            if (!normalized.isEmpty()) {
                                ftsProjected.put("tokenizer", JsonString(normalized))
                            }
                        case None => ()
                    }
                    if (ftsProjected.toJsonString() != "{}") {
                        storeProjected.put("fts", ftsProjected)
                    }
                case None => ()
            }
            match (cfgGetObject(storeRaw, "vector")) {
                case Some(vectorRaw) =>
                    let vectorProjected = JsonObject()
                    cfgCopyScalar(vectorRaw, "enabled", vectorProjected)
                    match (cfgGetString(vectorRaw, "extensionPath")) {
                        case Some(extensionPath) =>
                            let normalized = extensionPath.trimAscii()
                            if (!normalized.isEmpty()) {
                                vectorProjected.put("extensionPath", JsonString(normalized))
                            }
                        case None => ()
                    }
                    if (vectorProjected.toJsonString() != "{}") {
                        storeProjected.put("vector", vectorProjected)
                    }
                case None => ()
            }
            if (storeProjected.toJsonString() != "{}") {
                projected.put("store", storeProjected)
            }
        case None => ()
    }
    match (cfgGetObject(obj, "sync")) {
        case Some(syncRaw) =>
            let syncProjected = JsonObject()
            cfgCopyScalar(syncRaw, "onSessionStart", syncProjected)
            cfgCopyScalar(syncRaw, "onSearch", syncProjected)
            cfgCopyScalar(syncRaw, "watch", syncProjected)
            cfgCopyScalar(syncRaw, "watchDebounceMs", syncProjected)
            cfgCopyScalar(syncRaw, "intervalMinutes", syncProjected)
            match (cfgGetObject(syncRaw, "sessions")) {
                case Some(sessionsRaw) =>
                    let sessionsProjected = JsonObject()
                    cfgCopyScalar(sessionsRaw, "deltaBytes", sessionsProjected)
                    cfgCopyScalar(sessionsRaw, "deltaMessages", sessionsProjected)
                    cfgCopyScalar(sessionsRaw, "postCompactionForce", sessionsProjected)
                    if (sessionsProjected.toJsonString() != "{}") {
                        syncProjected.put("sessions", sessionsProjected)
                    }
                case None => ()
            }
            if (syncProjected.toJsonString() != "{}") {
                projected.put("sync", syncProjected)
            }
        case None => ()
    }
    match (cfgGetObject(obj, "multimodal")) {
        case Some(multimodalRaw) =>
            let multimodalProjected = JsonObject()
            cfgCopyScalar(multimodalRaw, "enabled", multimodalProjected)
            cfgCopyScalar(multimodalRaw, "maxFileBytes", multimodalProjected)
            match (cfgGetStringArray(multimodalRaw, "modalities")) {
                case Some(modalities) =>
                    let arr = JsonArray([])
                    for (modality in modalities) {
                        arr.add(JsonString(modality))
                    }
                    multimodalProjected.put("modalities", arr)
                case None => ()
            }
            if (multimodalProjected.toJsonString() != "{}") {
                projected.put("multimodal", multimodalProjected)
            }
        case None => ()
    }
    if (projected.toJsonString() == "{}") {
        return None
    }
    Some(projected)
}

private func mergeUniqueStringArrays(base: Array<String>, extra: Array<String>): Array<String> {
    let merged = ArrayList<String>()
    for (values in [base, extra]) {
        for (value in values) {
            let normalized = value.trimAscii()
            if (normalized.isEmpty()) {
                continue
            }
            var seen = false
            for (existing in merged) {
                if (existing == normalized) {
                    seen = true
                    break
                }
            }
            if (!seen) {
                merged.add(normalized)
            }
        }
    }
    merged.toArray()
}

private func cfgEnsureObject(root: JsonObject, key: String): JsonObject {
    match (root.get(key)) {
        case Some(value) =>
            try {
                value.asObject()
            } catch (_: Exception) {
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

private func rootHasExplicitUserConfig(root: JsonObject): Bool {
    for (key in ["gateway", "session", "tools", "models", "auth", "channels", "plugins", "wizard", "memory"]) {
        match (cfgGetObject(root, key)) {
            case Some(obj) =>
                if (obj.toJsonString() != "{}") {
                    return true
                }
            case None => ()
        }
    }
    false
}

private func isLegacyArkQwenModelRef(raw: String): Bool {
    let trimmed = raw.trimAscii()
    if (!trimmed.contains(":")) {
        return false
    }
    let parts = trimmed.split(":")
    if (parts.size < 2) {
        return false
    }
    let provider = parts[0].trimAscii().toAsciiLower()
    let model = String.join(parts[1..parts.size], delimiter: ":").trimAscii().toAsciiLower()
    provider == "ark" && (model.startsWith("qwen") || model.startsWith("qwq"))
}

private func cleanedPrimaryModelRef(raw: String): String {
    let trimmed = raw.trimAscii()
    if (!isLegacyArkQwenModelRef(trimmed)) {
        return trimmed
    }
    let parts = trimmed.split(":")
    if (parts.size < 2) {
        return trimmed
    }
    let model = String.join(parts[1..parts.size], delimiter: ":").trimAscii()
    if (model.isEmpty()) {
        return trimmed
    }
    "qwen:${model}"
}

private func normalizeLegacyModelRef(raw: String): String {
    let trimmed = cleanedPrimaryModelRef(raw)
    if (trimmed.isEmpty()) {
        return trimmed
    }
    if (trimmed.contains(":")) {
        let parts = trimmed.split(":")
        if (parts.size < 2) {
            return trimmed
        }
        let provider = parts[0].trimAscii().toAsciiLower()
        let model = String.join(parts[1..parts.size], delimiter: ":").trimAscii()
        let mappedProvider = cliRuntimeModelProviderId(provider)
        if (model.isEmpty() || mappedProvider.isEmpty()) {
            return trimmed
        }
        return "${mappedProvider}:${model}"
    }
    if (!trimmed.contains("/")) {
        return trimmed
    }
    let parts = trimmed.split("/")
    if (parts.size < 2) {
        return trimmed
    }
    let provider = parts[0].trimAscii().toAsciiLower()
    let model = String.join(parts[1..parts.size], delimiter: "/").trimAscii()
    let mappedProvider = cliRuntimeModelProviderId(provider)
    if (model.isEmpty()) {
        trimmed
    } else {
        "${mappedProvider}:${model}"
    }
}

private func canonicalLegacyProviderId(raw: String): String {
    cliCanonicalModelProviderId(raw)
}

private func writeRuntimeEnvIfMissing(key: String, value: String): Unit {
    let normalizedKey = key.trimAscii()
    let normalizedValue = value.trimAscii()
    if (normalizedKey.isEmpty() || normalizedValue.isEmpty()) {
        return
    }
    let existing = (Config.env[normalizedKey] ?? "").trimAscii()
    if (existing.isEmpty()) {
        Config.env[normalizedKey] = normalizedValue
    }
}

private func materializeProviderRuntimeEnvFromConfig(root: JsonObject, providerId: String): Unit {
    let apiKey = match (cfgGetProviderField(root, providerId, "apiKey")) {
        case Some(value) => value.trimAscii()
        case None => ""
    }
    let baseUrl = match (cfgGetProviderField(root, providerId, "baseUrl")) {
        case Some(value) => value.trimAscii()
        case None => ""
    }
    for (alias in cliProviderApiKeyEnvAliases(providerId)) {
        writeRuntimeEnvIfMissing(alias, apiKey)
    }
    for (alias in cliProviderBaseUrlEnvAliases(providerId)) {
        writeRuntimeEnvIfMissing(alias, baseUrl)
    }
}

private func canonicalLegacyModelRef(raw: String): String {
    let trimmed = cleanedPrimaryModelRef(raw)
    if (trimmed.isEmpty()) {
        return trimmed
    }
    if (trimmed.contains(":")) {
        let parts = trimmed.split(":")
        if (parts.size < 2) {
            return trimmed
        }
        let provider = canonicalLegacyProviderId(parts[0])
        let model = String.join(parts[1..parts.size], delimiter: ":").trimAscii()
        return if (model.isEmpty()) { provider } else { "${provider}:${model}" }
    }
    if (trimmed.contains("/")) {
        let parts = trimmed.split("/")
        if (parts.size < 2) {
            return trimmed
        }
        let provider = canonicalLegacyProviderId(parts[0])
        let model = String.join(parts[1..parts.size], delimiter: "/").trimAscii()
        return if (model.isEmpty()) { provider } else { "${provider}:${model}" }
    }
    canonicalLegacyProviderId(trimmed)
}

private func modelRefProviderId(raw: String): String {
    let canonical = canonicalLegacyModelRef(raw).trimAscii()
    if (canonical.contains(":")) {
        let parts = canonical.split(":")
        if (parts.size >= 1) {
            return canonicalLegacyProviderId(parts[0])
        }
    }
    if (canonical.contains("/")) {
        let parts = canonical.split("/")
        if (parts.size >= 1) {
            return canonicalLegacyProviderId(parts[0])
        }
    }
    canonicalLegacyProviderId(canonical)
}

private func cfgGetProviderField(root: JsonObject, providerId: String, field: String): Option<String> {
    match (cfgGetObject(root, "models")) {
        case Some(modelsObj) =>
            match (cfgGetObject(modelsObj, "providers")) {
                case Some(providersObj) =>
                    match (cfgGetObject(providersObj, providerId)) {
                        case Some(providerObj) => cfgGetString(providerObj, field)
                        case None => None
                    }
                case None => None
            }
        case None => None
    }
}

private func cfgGetContext7ApiKey(root: JsonObject): Option<String> {
    match (cfgGetObject(root, "tools")) {
        case Some(toolsObj) =>
            match (cfgGetObject(toolsObj, "context7")) {
                case Some(context7Obj) =>
                    match (cfgGetString(context7Obj, "apiKey")) {
                        case Some(value) =>
                            let trimmed = value.trimAscii()
                            if (!trimmed.isEmpty()) {
                                Some(trimmed)
                            } else {
                                None
                            }
                        case None => None
                    }
                case None => None
            }
        case None => None
    }
}

private func cfgGetTavilyApiKey(root: JsonObject): Option<String> {
    match (cfgGetObject(root, "tools")) {
        case Some(toolsObj) =>
            match (cfgGetObject(toolsObj, "search")) {
                case Some(searchObj) =>
                    match (cfgGetObject(searchObj, "tavily")) {
                        case Some(tavilyObj) =>
                            match (cfgGetString(tavilyObj, "apiKey")) {
                                case Some(value) =>
                                    let trimmed = value.trimAscii()
                                    if (!trimmed.isEmpty()) {
                                        Some(trimmed)
                                    } else {
                                        None
                                    }
                                case None => None
                            }
                        case None => None
                    }
                case None => None
            }
        case None => None
    }
}

private func cfgGetProviderFieldFromRaw(providerId: String, field: String): Option<String> {
    match (MetisConfigManager.rawConfig()) {
        case Some(root) =>
            match (cfgGetProviderField(root, cliCanonicalModelProviderId(providerId), field)) {
                case Some(value) =>
                    let trimmed = value.trimAscii()
                    if (trimmed.isEmpty()) {
                        None
                    } else {
                        Some(MetisConfigManager.normalizeConfigPathValue(trimmed))
                    }
                case None => None
            }
        case None => None
    }
}

public class MetisConfigManager {
    private static var _raw: Option<JsonObject> = None
    private static var _rawLoadAttempted: Bool = false
    private static var _rawExists: Bool = false
    private static var _rawParseError: String = ""
    private static var _writeRootNotificationHook: Option<(MetisConfigWriteNotification) -> Unit> =
        None<(MetisConfigWriteNotification) -> Unit>

    public static func configPath(): Path {
        MetisPaths.configPath()
    }

    public static func setWriteRootNotificationHook(listener: Option<(MetisConfigWriteNotification) -> Unit>): Unit {
        _writeRootNotificationHook = listener
    }

    public static func rawConfig(): Option<JsonObject> {
        if (_rawLoadAttempted) {
            return _raw
        }
        _rawLoadAttempted = true
        if (let Some(raw) <- _raw) {
            return raw
        }
        let path = MetisPaths.configPathReadOnly()
        _rawExists = exists(path)
        if (!_rawExists) {
            _rawParseError = ""
            return None
        }
        try {
            let text = String.fromUtf8(File.readFrom(path))
            let json = JsonValue.fromStr(text).asObject()
            _rawParseError = ""
            _raw = json
            json
        } catch (e: Exception) {
            _rawParseError = e.message
            LogUtils.error("Failed to load metis.json: ${e.message}")
            None
        }
    }

    private static func mutableRoot(): JsonObject {
        initializeIfMissing()
        match (rawConfig()) {
            case Some(root) => root
            case None =>
                if (_rawExists && !_rawParseError.isEmpty()) {
                    throw Exception(
                        "Refusing to mutate metis.json because it is invalid: ${_rawParseError}"
                    )
                }
                JsonObject()
        }
    }

    private static func hasConfigObjectPath(root: JsonObject, path: Array<String>): Bool {
        var current = root
        for (i in 0..path.size) {
            let key = path[i]
            match (current.get(key)) {
                case Some(value) =>
                    if (i == path.size - 1) {
                        try {
                            let _ = value.asObject()
                            return true
                        } catch (_: Exception) {
                            return false
                        }
                    }
                    try {
                        current = value.asObject()
                    } catch (_: Exception) {
                        return false
                    }
                case None => return false
            }
        }
        false
    }

    private static func assertGatewayPatchRootIsComplete(root: JsonObject): Unit {
        if (!_rawExists) {
            return
        }
        if (!hasConfigObjectPath(root, ["agents", "defaults"])) {
            throw Exception(
                "Refusing to mutate gateway settings because metis.json is missing agents.defaults; " +
                "gateway persistence requires a complete config snapshot."
            )
        }
    }

    public static func currentConfigParseError(): Option<String> {
        let _ = rawConfig()
        if (_rawExists && !_rawParseError.isEmpty()) {
            return Some(_rawParseError)
        }
        None
    }

    public static func invalidate(): Unit {
        _raw = None
        _rawLoadAttempted = false
        _rawExists = false
        _rawParseError = ""
    }

    private static func migrateLegacyInto(root: JsonObject): Bool {
        var changed = false
        match (cfgGetObject(root, "agents")) {
            case Some(agents) =>
                match (cfgGetObject(agents, "defaults")) {
                    case Some(defaults) =>
                        match (cfgGetObject(defaults, "model")) {
                            case Some(model) =>
                                match (cfgGetString(model, "primary")) {
                                    case Some(primary) =>
                                        let cleaned = cleanedPrimaryModelRef(primary)
                                        if (!cleaned.isEmpty() && cleaned != primary.trimAscii()) {
                                            model.put("primary", JsonString(storageModelRef(cleaned)))
                                            defaults.put("model", model)
                                            agents.put("defaults", defaults)
                                            root.put("agents", agents)
                                            changed = true
                                        }
                                    case None => ()
                                }
                            case None => ()
                        }
                    case None => ()
                }
            case None => ()
        }
        changed
    }

    public static func migrateLegacyIfNeeded(): Unit {
        let path = configPath()
        if (!exists(path)) {
            return
        }
        let root = loadRootForMigration()
        if (migrateLegacyInto(root)) {
            File.writeTo(path, root.toJsonString().toArray())
            _raw = root
        }
    }

    private static func loadRootForMigration(): JsonObject {
        match (rawConfig()) {
            case Some(root) => root
            case None => JsonObject()
        }
    }

    public static func readPrimaryModel(): Option<String> {
        match (rawConfig()) {
            case Some(root) =>
                match (cfgGetObject(root, "agents")) {
                    case Some(agents) =>
                        match (cfgGetObject(agents, "defaults")) {
                            case Some(defaults) =>
                                match (cfgGetObject(defaults, "model")) {
                                    case Some(model) =>
                                        cfgGetString(model, "primary")
                                    case None => None
                                }
                            case None => None
                        }
                    case None => None
                }
            case None => None
        }
    }

    public static func readFallbackModels(): Array<String> {
        match (rawConfig()) {
            case Some(root) =>
                match (cfgGetObject(root, "agents")) {
                    case Some(agents) =>
                        match (cfgGetObject(agents, "defaults")) {
                            case Some(defaults) =>
                                match (cfgGetObject(defaults, "model")) {
                                    case Some(model) =>
                                        match (model.get("fallbacks")) {
                                            case Some(value) =>
                                                try {
                                                    let arr = value.asArray()
                                                    let out = ArrayList<String>()
                                                    for (item in arr.getItems()) {
                                                        try {
                                                            let text = normalizeLegacyModelRef(item.asString().getValue()).trimAscii()
                                                            if (!text.isEmpty()) {
                                                                out.add(text)
                                                            }
                                                        } catch (_: Exception) {
                                                            ()
                                                        }
                                                    }
                                                    out.toArray()
                                                } catch (_: Exception) {
                                                    Array<String>()
                                                }
                                            case None => Array<String>()
                                        }
                                    case None => Array<String>()
                                }
                            case None => Array<String>()
                        }
                    case None => Array<String>()
                }
            case None => Array<String>()
        }
    }

    public static func readImageModel(): Option<String> {
        match (rawConfig()) {
            case Some(root) =>
                match (cfgGetObject(root, "agents")) {
                    case Some(agents) =>
                        match (cfgGetObject(agents, "defaults")) {
                            case Some(defaults) =>
                                match (cfgGetObject(defaults, "imageModel")) {
                                    case Some(model) =>
                                        match (cfgGetString(model, "primary")) {
                                            case Some(value) =>
                                                let normalized = normalizeLegacyModelRef(value).trimAscii()
                                                if (normalized.isEmpty()) { None } else { Some(normalized) }
                                            case None => None
                                        }
                                    case None => None
                                }
                            case None => None
                        }
                    case None => None
                }
            case None => None
        }
    }

    public static func readImageFallbackModels(): Array<String> {
        match (rawConfig()) {
            case Some(root) =>
                match (cfgGetObject(root, "agents")) {
                    case Some(agents) =>
                        match (cfgGetObject(agents, "defaults")) {
                            case Some(defaults) =>
                                match (cfgGetObject(defaults, "imageModel")) {
                                    case Some(model) =>
                                        match (model.get("fallbacks")) {
                                            case Some(value) =>
                                                try {
                                                    let arr = value.asArray()
                                                    let out = ArrayList<String>()
                                                    let seen = ArrayList<String>()
                                                    for (item in arr.getItems()) {
                                                        try {
                                                            let text = normalizeLegacyModelRef(item.asString().getValue()).trimAscii()
                                                            if (!text.isEmpty() && !seen.contains(text)) {
                                                                seen.add(text)
                                                                out.add(text)
                                                            }
                                                        } catch (_: Exception) {
                                                            ()
                                                        }
                                                    }
                                                    out.toArray()
                                                } catch (_: Exception) {
                                                    Array<String>()
                                                }
                                            case None => Array<String>()
                                        }
                                    case None => Array<String>()
                                }
                            case None => Array<String>()
                        }
                    case None => Array<String>()
                }
            case None => Array<String>()
        }
    }

    public static func readWorkspace(): Option<String> {
        match (rawConfig()) {
            case Some(root) =>
                match (cfgGetObject(root, "agents")) {
                    case Some(agents) =>
                        match (cfgGetObject(agents, "defaults")) {
                            case Some(defaults) =>
                                match (cfgGetString(defaults, "workspace")) {
                                    case Some(workspace) => Some(workspace.trimAscii())
                                    case None => None
                                }
                            case None => None
                        }
                    case None => None
                }
            case None => None
        }
    }

    public static func readFastModel(): Option<String> {
        match (rawConfig()) {
            case Some(root) =>
                match (root.get("fastModel")) {
                    case Some(value) =>
                        try {
                            let normalized = normalizeLegacyModelRef(value.asString().getValue()).trimAscii()
                            if (normalized.isEmpty()) {
                                None
                            } else {
                                Some(normalized)
                            }
                        } catch (_: Exception) {
                            None
                        }
                    case None => None
                }
            case None => None
        }
    }

    public static func readTemperature(): Option<Float64> {
        match (rawConfig()) {
            case Some(root) =>
                match (root.get("temperature")) {
                    case Some(value) =>
                        try {
                            Some(Float64.parse(value.toJsonString()))
                        } catch (_: Exception) {
                            None
                        }
                    case None => None
                }
            case None => None
        }
    }

    public static func readDefaultModelInputLimit(): Option<Int64> {
        match (rawConfig()) {
            case Some(root) =>
                match (root.get("defaultModelInputLimit")) {
                    case Some(value) =>
                        try {
                            Some(value.asInt().getValue())
                        } catch (_: Exception) {
                            None
                        }
                    case None => None
                }
            case None => None
        }
    }

    public static func readDefaultModelOutputLimit(): Option<Int64> {
        match (rawConfig()) {
            case Some(root) =>
                match (root.get("defaultModelOutputLimit")) {
                    case Some(value) =>
                        try {
                            Some(value.asInt().getValue())
                        } catch (_: Exception) {
                            None
                        }
                    case None => None
                }
            case None => None
        }
    }

    public static func readDefaultAgentSkills(): Option<Array<String>> {
        match (rawConfig()) {
            case Some(root) =>
                match (cfgGetObject(root, "agents")) {
                    case Some(agents) =>
                        match (cfgGetObject(agents, "defaults")) {
                            case Some(defaults) => cfgGetStringArray(defaults, "skills")
                            case None => None<Array<String>>
                        }
                    case None => None<Array<String>>
                }
            case None => None<Array<String>>
        }
    }

    public static func readDefaultMemorySearch(): Option<JsonObject> {
        match (rawConfig()) {
            case Some(root) =>
                match (cfgGetObject(root, "agents")) {
                    case Some(agents) =>
                        match (cfgGetObject(agents, "defaults")) {
                            case Some(defaults) =>
                                match (cfgGetObject(defaults, "memorySearch")) {
                                    case Some(memorySearch) => projectMemorySearchConfig(memorySearch)
                                    case None => None<JsonObject>
                                }
                            case None => None<JsonObject>
                        }
                    case None => None<JsonObject>
                }
            case None => None<JsonObject>
        }
    }

    public static func resolveAgentSkillsFromRoot(root: JsonObject, agentId: String): Option<Array<String>> {
        let normalizedAgentId = normalizeAgentConfigId(agentId)
        let defaultSkills: Option<Array<String>> = match (cfgGetObject(root, "agents")) {
            case Some(agents) =>
                match (cfgGetObject(agents, "defaults")) {
                    case Some(defaults) => cfgGetStringArray(defaults, "skills")
                    case None => None<Array<String>>
                }
            case None => None<Array<String>>
        }
        if (normalizedAgentId.isEmpty()) {
            return defaultSkills
        }
        match (cfgGetObject(root, "agents")) {
            case Some(agents) =>
                match (agents.get("list")) {
                    case Some(listValue) =>
                        try {
                            let entries = listValue.asArray()
                            for (item in entries.getItems()) {
                                let entry = try {
                                    item.asObject()
                                } catch (_: Exception) {
                                    continue
                                }
                                if (normalizeAgentConfigId(cfgGetString(entry, "id") ?? "") != normalizedAgentId) {
                                    continue
                                }
                                match (resolveAgentSkillsOverride(entry)) {
                                    case Some(skills) => return Some(skills)
                                    case None => return defaultSkills
                                }
                            }
                            defaultSkills
                        } catch (_: Exception) {
                            defaultSkills
                        }
                    case None => defaultSkills
                }
            case None => defaultSkills
        }
    }

    public static func resolveAgentMemorySearchFromRoot(root: JsonObject, agentId: String): Option<JsonObject> {
        let normalizedAgentId = normalizeAgentConfigId(agentId)
        let defaultMemorySearch: Option<JsonObject> = match (cfgGetObject(root, "agents")) {
            case Some(agents) =>
                match (cfgGetObject(agents, "defaults")) {
                    case Some(defaults) =>
                        match (cfgGetObject(defaults, "memorySearch")) {
                            case Some(memorySearch) => projectMemorySearchConfig(memorySearch)
                            case None => None<JsonObject>
                        }
                    case None => None<JsonObject>
                }
            case None => None<JsonObject>
        }
        if (normalizedAgentId.isEmpty()) {
            return defaultMemorySearch
        }
        match (cfgGetObject(root, "agents")) {
            case Some(agents) =>
                match (agents.get("list")) {
                    case Some(listValue) =>
                        try {
                            let entries = listValue.asArray()
                            for (item in entries.getItems()) {
                                let entry = try {
                                    item.asObject()
                                } catch (_: Exception) {
                                    continue
                                }
                                if (normalizeAgentConfigId(cfgGetString(entry, "id") ?? "") != normalizedAgentId) {
                                    continue
                                }
                                match (cfgGetObject(entry, "memorySearch")) {
                                    case Some(memorySearch) =>
                                        let projected = projectMemorySearchConfig(memorySearch)
                                        match (defaultMemorySearch) {
                                            case Some(defaultCfg) =>
                                                let merged = JsonObject()
                                                match (cfgGetString(defaultCfg, "provider")) {
                                                    case Some(provider) => merged.put("provider", JsonString(provider.trimAscii()))
                                                    case None => ()
                                                }
                                                match (cfgGetBool(defaultCfg, "enabled")) {
                                                    case Some(enabled) => merged.put("enabled", enabled.toJsonValue())
                                                    case None => ()
                                                }
                                                match (cfgGetString(defaultCfg, "model")) {
                                                    case Some(model) => merged.put("model", JsonString(model.trimAscii()))
                                                    case None => ()
                                                }
                                                cfgCopyScalar(defaultCfg, "outputDimensionality", merged)
                                                match (defaultCfg.get("fallback")) {
                                                    case Some(value) =>
                                                        try {
                                                            merged.put("fallback", JsonString(value.asString().getValue().trimAscii()))
                                                        } catch (_: Exception) {
                                                            ()
                                                        }
                                                    case None => ()
                                                }
                                                let defaultExtraPaths = cfgGetStringArray(defaultCfg, "extraPaths") ?? Array<String>()
                                                let defaultQmdExtraCollections = match (cfgGetObject(defaultCfg, "qmd")) {
                                                    case Some(qmd) => cfgGetStringArray(qmd, "extraCollections") ?? Array<String>()
                                                    case None => Array<String>()
                                                }
                                                match (cfgGetObject(defaultCfg, "local")) {
                                                    case Some(local) => merged.put("local", local)
                                                    case None => ()
                                                }
                                                match (cfgGetObject(defaultCfg, "query")) {
                                                    case Some(query) => merged.put("query", query)
                                                    case None => ()
                                                }
                                                match (cfgGetObject(defaultCfg, "store")) {
                                                    case Some(store) => merged.put("store", store)
                                                    case None => ()
                                                }
                                                match (cfgGetObject(defaultCfg, "sync")) {
                                                    case Some(sync) => merged.put("sync", sync)
                                                    case None => ()
                                                }
                                                let defaultMultimodal = cfgGetObject(defaultCfg, "multimodal")
                                                match (projected) {
                                                    case Some(overrideCfg) =>
                                                        match (cfgGetString(overrideCfg, "provider")) {
                                                            case Some(provider) => merged.put("provider", JsonString(provider.trimAscii()))
                                                            case None => ()
                                                        }
                                                        match (cfgGetBool(overrideCfg, "enabled")) {
                                                            case Some(enabled) => merged.put("enabled", enabled.toJsonValue())
                                                            case None => ()
                                                        }
                                                        match (cfgGetString(overrideCfg, "model")) {
                                                            case Some(model) => merged.put("model", JsonString(model.trimAscii()))
                                                            case None => ()
                                                        }
                                                        cfgCopyScalar(overrideCfg, "outputDimensionality", merged)
                                                        match (overrideCfg.get("fallback")) {
                                                            case Some(value) =>
                                                                try {
                                                                    merged.put("fallback", JsonString(value.asString().getValue().trimAscii()))
                                                                } catch (_: Exception) {
                                                                    ()
                                                                }
                                                            case None => ()
                                                        }
                                                        let mergedExtraPaths = mergeUniqueStringArrays(
                                                            defaultExtraPaths,
                                                            cfgGetStringArray(overrideCfg, "extraPaths") ?? Array<String>()
                                                        )
                                                        if (!mergedExtraPaths.isEmpty()) {
                                                            let arr = JsonArray([])
                                                            for (path in mergedExtraPaths) {
                                                                arr.add(JsonString(path))
                                                            }
                                                            merged.put("extraPaths", arr)
                                                        }
                                                        let overrideQmdExtraCollections = match (cfgGetObject(overrideCfg, "qmd")) {
                                                            case Some(qmd) => cfgGetStringArray(qmd, "extraCollections") ?? Array<String>()
                                                            case None => Array<String>()
                                                        }
                                                        let mergedQmdExtraCollections = mergeUniqueStringArrays(
                                                            defaultQmdExtraCollections,
                                                            overrideQmdExtraCollections
                                                        )
                                                        if (!mergedQmdExtraCollections.isEmpty()) {
                                                            let qmd = JsonObject()
                                                            let arr = JsonArray([])
                                                            for (collection in mergedQmdExtraCollections) {
                                                                arr.add(JsonString(collection))
                                                            }
                                                            qmd.put("extraCollections", arr)
                                                            merged.put("qmd", qmd)
                                                        }
                                                        match (cfgGetObject(overrideCfg, "remote")) {
                                                            case Some(remote) => merged.put("remote", remote)
                                                            case None => ()
                                                        }
                                                        match (cfgGetObject(overrideCfg, "local")) {
                                                            case Some(local) => merged.put("local", local)
                                                            case None => ()
                                                        }
                                                        match (cfgGetObject(overrideCfg, "query")) {
                                                            case Some(query) => merged.put("query", query)
                                                            case None => ()
                                                        }
                                                        match (cfgGetObject(overrideCfg, "store")) {
                                                            case Some(store) => merged.put("store", store)
                                                            case None => ()
                                                        }
                                                        match (cfgGetObject(overrideCfg, "sync")) {
                                                            case Some(sync) => merged.put("sync", sync)
                                                            case None => ()
                                                        }
                                                        let mergedMultimodal = JsonObject()
                                                        match (defaultMultimodal) {
                                                            case Some(multimodal) =>
                                                                cfgCopyScalar(multimodal, "enabled", mergedMultimodal)
                                                                cfgCopyScalar(multimodal, "maxFileBytes", mergedMultimodal)
                                                                match (cfgGetStringArray(multimodal, "modalities")) {
                                                                    case Some(modalities) =>
                                                                        let arr = JsonArray([])
                                                                        for (modality in modalities) {
                                                                            arr.add(JsonString(modality))
                                                                        }
                                                                        mergedMultimodal.put("modalities", arr)
                                                                    case None => ()
                                                                }
                                                            case None => ()
                                                        }
                                                        match (cfgGetObject(overrideCfg, "multimodal")) {
                                                            case Some(multimodal) =>
                                                                cfgCopyScalar(multimodal, "enabled", mergedMultimodal)
                                                                cfgCopyScalar(multimodal, "maxFileBytes", mergedMultimodal)
                                                                match (cfgGetStringArray(multimodal, "modalities")) {
                                                                    case Some(modalities) =>
                                                                        let arr = JsonArray([])
                                                                        for (modality in modalities) {
                                                                            arr.add(JsonString(modality))
                                                                        }
                                                                        mergedMultimodal.put("modalities", arr)
                                                                    case None => ()
                                                                }
                                                            case None => ()
                                                        }
                                                        if (mergedMultimodal.toJsonString() != "{}") {
                                                            merged.put("multimodal", mergedMultimodal)
                                                        }
                                                    case None => ()
                                                }
                                                if (merged.get("extraPaths").isNone()) {
                                                    if (!defaultExtraPaths.isEmpty()) {
                                                        let arr = JsonArray([])
                                                        for (path in defaultExtraPaths) {
                                                            arr.add(JsonString(path))
                                                        }
                                                        merged.put("extraPaths", arr)
                                                    }
                                                }
                                                if (merged.get("qmd").isNone()) {
                                                    if (!defaultQmdExtraCollections.isEmpty()) {
                                                        let qmd = JsonObject()
                                                        let arr = JsonArray([])
                                                        for (collection in defaultQmdExtraCollections) {
                                                            arr.add(JsonString(collection))
                                                        }
                                                        qmd.put("extraCollections", arr)
                                                        merged.put("qmd", qmd)
                                                    }
                                                }
                                                if (merged.get("remote").isNone()) {
                                                    match (cfgGetObject(defaultCfg, "remote")) {
                                                        case Some(remote) => merged.put("remote", remote)
                                                        case None => ()
                                                    }
                                                }
                                                return if (merged.toJsonString() == "{}") { None<JsonObject> } else { Some(merged) }
                                            case None => return projected
                                        }
                                    case None => return defaultMemorySearch
                                }
                            }
                            defaultMemorySearch
                        } catch (_: Exception) {
                            defaultMemorySearch
                        }
                    case None => defaultMemorySearch
                }
            case None => defaultMemorySearch
        }
    }

    public static func readAgentSkills(agentId: String): Option<Array<String>> {
        let normalizedAgentId = normalizeAgentConfigId(agentId)
        if (normalizedAgentId.isEmpty()) {
            return None<Array<String>>
        }
        match (rawConfig()) {
            case Some(root) => resolveAgentSkillsFromRoot(root, normalizedAgentId)
            case None => None<Array<String>>
        }
    }

    public static func readAgentMemorySearch(agentId: String): Option<JsonObject> {
        let normalizedAgentId = normalizeAgentConfigId(agentId)
        match (rawConfig()) {
            case Some(root) => resolveAgentMemorySearchFromRoot(root, normalizedAgentId)
            case None => None<JsonObject>
        }
    }

    public static func resolveAgentSkillsScopeFromRoot(root: JsonObject, agentId: String): String {
        let normalizedAgentId = normalizeAgentConfigId(agentId)
        let hasDefaults = match (cfgGetObject(root, "agents")) {
            case Some(agents) =>
                match (cfgGetObject(agents, "defaults")) {
                    case Some(defaults) => cfgGetStringArray(defaults, "skills").isSome()
                    case None => false
                }
            case None => false
        }
        if (normalizedAgentId.isEmpty()) {
            return if (hasDefaults) { "default" } else { "unrestricted" }
        }
        match (cfgGetObject(root, "agents")) {
            case Some(agents) =>
                match (agents.get("list")) {
                    case Some(listValue) =>
                        try {
                            let entries = listValue.asArray()
                            for (item in entries.getItems()) {
                                let entry = try {
                                    item.asObject()
                                } catch (_: Exception) {
                                    continue
                                }
                                if (normalizeAgentConfigId(cfgGetString(entry, "id") ?? "") != normalizedAgentId) {
                                    continue
                                }
                                return if (entry.get("skills").isSome()) { "explicit" } else if (hasDefaults) { "default" } else { "unrestricted" }
                            }
                        } catch (_: Exception) {
                            ()
                        }
                    case None => ()
                }
            case None => ()
        }
        if (hasDefaults) { "default" } else { "unrestricted" }
    }

    public static func resolveAgentMemorySearchScopeFromRoot(root: JsonObject, agentId: String): String {
        let normalizedAgentId = normalizeAgentConfigId(agentId)
        let hasDefaults = match (cfgGetObject(root, "agents")) {
            case Some(agents) =>
                match (cfgGetObject(agents, "defaults")) {
                    case Some(defaults) => cfgGetObject(defaults, "memorySearch").isSome()
                    case None => false
                }
            case None => false
        }
        if (normalizedAgentId.isEmpty()) {
            return if (hasDefaults) { "agents.defaults.memorySearch" } else { "unconfigured" }
        }
        match (cfgGetObject(root, "agents")) {
            case Some(agents) =>
                match (agents.get("list")) {
                    case Some(listValue) =>
                        try {
                            let entries = listValue.asArray()
                            for (item in entries.getItems()) {
                                let entry = try {
                                    item.asObject()
                                } catch (_: Exception) {
                                    continue
                                }
                                if (normalizeAgentConfigId(cfgGetString(entry, "id") ?? "") != normalizedAgentId) {
                                    continue
                                }
                                return if (entry.get("memorySearch").isSome()) {
                                    "agents.list[].memorySearch"
                                } else if (hasDefaults) {
                                    "agents.defaults.memorySearch"
                                } else {
                                    "unconfigured"
                                }
                            }
                        } catch (_: Exception) {
                            ()
                        }
                    case None => ()
                }
            case None => ()
        }
        if (hasDefaults) { "agents.defaults.memorySearch" } else { "unconfigured" }
    }

    public static func readAgentSkillsScope(agentId: String): String {
        let normalizedAgentId = normalizeAgentConfigId(agentId)
        if (normalizedAgentId.isEmpty()) {
            return "unrestricted"
        }
        match (rawConfig()) {
            case Some(root) => resolveAgentSkillsScopeFromRoot(root, normalizedAgentId)
            case None => "unrestricted"
        }
    }

    public static func readAgentMemorySearchScope(agentId: String): String {
        let normalizedAgentId = normalizeAgentConfigId(agentId)
        match (rawConfig()) {
            case Some(root) => resolveAgentMemorySearchScopeFromRoot(root, normalizedAgentId)
            case None => "unconfigured"
        }
    }

    public static func readMemoryPluginSlot(): String {
        match (rawConfig()) {
            case Some(root) =>
                match (cfgGetObject(root, "plugins")) {
                    case Some(plugins) =>
                        match (cfgGetObject(plugins, "slots")) {
                            case Some(slots) =>
                                match (cfgGetString(slots, "memory")) {
                                    case Some(slot) =>
                                        let normalized = slot.trimAscii()
                                        if (normalized.isEmpty()) { "memory-core" } else { normalized }
                                    case None => "memory-core"
                                }
                            case None => "memory-core"
                        }
                    case None => "memory-core"
                }
            case None => "memory-core"
        }
    }

    public static func readMemoryPluginConfig(pluginId: String): Option<JsonObject> {
        let normalizedPluginId = pluginId.trimAscii()
        if (normalizedPluginId.isEmpty() || normalizedPluginId == "none") {
            return None
        }
        match (rawConfig()) {
            case Some(root) =>
                match (cfgGetObject(root, "plugins")) {
                    case Some(plugins) =>
                        match (cfgGetObject(plugins, "entries")) {
                            case Some(entries) =>
                                match (cfgGetObject(entries, normalizedPluginId)) {
                                    case Some(entry) => cfgGetObject(entry, "config")
                                    case None => None
                                }
                            case None => None
                        }
                    case None => None
                }
            case None => None
        }
    }

    public static func readMemoryPluginEnabled(pluginId: String): Bool {
        let normalizedPluginId = pluginId.trimAscii()
        if (normalizedPluginId.isEmpty()) {
            return false
        }
        if (normalizedPluginId == "none") {
            return false
        }
        match (rawConfig()) {
            case Some(root) =>
                match (cfgGetObject(root, "plugins")) {
                    case Some(plugins) =>
                        match (cfgGetObject(plugins, "entries")) {
                            case Some(entries) =>
                                match (cfgGetObject(entries, normalizedPluginId)) {
                                    case Some(entry) =>
                                        match (cfgGetBool(entry, "enabled")) {
                                            case Some(value) => value
                                            case None => true
                                        }
                                    case None => true
                                }
                            case None => true
                        }
                    case None => true
                }
            case None => true
        }
    }

    public static func readActiveMemoryPluginId(): String {
        let selected = readMemoryPluginSlot().trimAscii()
        if (selected == "none") {
            return "none"
        }
        if (!readMemoryPluginEnabled(selected)) {
            return "none"
        }
        if (selected.isEmpty()) {
            return "memory-core"
        }
        selected
    }

    public static func normalizeConfigPathValue(raw: String): String {
        raw.trimAscii()
    }

    public static func normalizeModelRef(raw: String): String {
        normalizeLegacyModelRef(raw)
    }

    public static func canonicalModelProviderId(raw: String): String {
        canonicalLegacyProviderId(raw)
    }

    public static func canonicalModelRef(raw: String): String {
        canonicalLegacyModelRef(raw)
    }

    public static func storageModelRef(raw: String): String {
        let canonical = canonicalModelRef(raw).trimAscii()
        if (canonical.contains(":")) {
            let parts = canonical.split(":")
            if (parts.size >= 2) {
                return "${parts[0]}/${String.join(parts[1..parts.size], delimiter: ":")}"
            }
        }
        canonical
    }

    public static func readProviderApiKey(providerId: String): String {
        match (cfgGetProviderFieldFromRaw(providerId, "apiKey")) {
            case Some(value) => return value
            case None => ()
        }
        ""
    }

    public static func readContext7ApiKey(): String {
        match (rawConfig()) {
            case Some(root) =>
                match (cfgGetContext7ApiKey(root)) {
                    case Some(value) => return value
                    case None => ()
                }
            case None => ()
        }
        ""
    }

    public static func readTavilyApiKey(): String {
        match (rawConfig()) {
            case Some(root) =>
                match (cfgGetTavilyApiKey(root)) {
                    case Some(value) => return value
                    case None => ()
                }
            case None => ()
        }
        ""
    }

    public static func readProviderBaseUrl(providerId: String): String {
        match (cfgGetProviderFieldFromRaw(providerId, "baseUrl")) {
            case Some(value) => return value
            case None => ()
        }
        ""
    }

    public static func applyPersistedFieldsToCliConfig(): Unit {
        match (rawConfig()) {
            case Some(root) =>
                for (descriptor in cliModelProviderCatalogDescriptors()) {
                    materializeProviderRuntimeEnvFromConfig(root, descriptor.providerId)
                }
            case None => ()
        }
        match (readPrimaryModel()) {
            case Some(model) =>
                let trimmed = normalizeLegacyModelRef(model)
                if (!trimmed.isEmpty()) {
                    CliConfig.model = trimmed
                }
            case None => ()
        }
        let persistedFallbacks = readFallbackModels()
        if (!persistedFallbacks.isEmpty()) {
            CliConfig.fallbackModels = persistedFallbacks
        }
        match (readImageModel()) {
            case Some(model) =>
                let trimmed = normalizeLegacyModelRef(model).trimAscii()
                if (!trimmed.isEmpty()) {
                    CliConfig.imageModel = trimmed
                }
            case None => ()
        }
        CliConfig.imageFallbackModels = readImageFallbackModels()
        match (readFastModel()) {
            case Some(model) =>
                let trimmed = model.trimAscii()
                if (!trimmed.isEmpty()) {
                    CliConfig.fastModel = Some(trimmed)
                }
            case None => ()
        }
        match (readTemperature()) {
            case Some(value) => CliConfig.temperature = value
            case None => ()
        }
        match (readDefaultModelInputLimit()) {
            case Some(value) => CliConfig.defaultModelInputLimit = value
            case None => ()
        }
        match (readDefaultModelOutputLimit()) {
            case Some(value) => CliConfig.defaultModelOutputLimit = value
            case None => ()
        }
        match (readWorkspace()) {
            case Some(workspace) =>
                let trimmed = workspace.trimAscii()
                if (!trimmed.isEmpty()) {
                    CliConfig.workspaceDirOverride = trimmed
                }
            case None => ()
        }
        CliModelRuntimeStateManager.writeMaterializedRuntimeState()
        CliModelRuntimeStateManager.applyRuntimeStateToCliConfig()
    }

    public static func initializeIfMissing(): Unit {
        let path = configPath()
        if (exists(path)) {
            return
        }
        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        defaults.put("workspace", JsonString(MetisPaths.workspaceRoot().toString()))
        let primary = try {
            CliConfig.model.trimAscii()
        } catch (_: Exception) {
            ""
        }
        if (!primary.isEmpty()) {
            let model = JsonObject()
            model.put("primary", JsonString(primary))
            defaults.put("model", model)
        }
        agents.put("defaults", defaults)
        root.put("agents", agents)
        root.put("gateway", JsonObject())
        root.put("session", JsonObject())
        root.put("skills", JsonObject())
        root.put("tools", JsonObject())
        root.put("models", JsonObject())
        root.put("auth", JsonObject())
        root.put("channels", JsonObject())
        root.put("plugins", JsonObject())
        root.put("wizard", JsonObject())
        root.put("meta", JsonObject())
        migrateLegacyInto(root)
        writeRoot(root)
    }

    public static func setWorkspace(workspace: String): String {
        let normalized = normalizeConfigPathValue(workspace).trimAscii()
        let nextWorkspace = if (normalized.isEmpty()) {
            MetisPaths.workspaceRoot().toString()
        } else {
            normalized
        }
        let root = mutableRoot()
        let agents = cfgEnsureObject(root, "agents")
        let defaults = cfgEnsureObject(agents, "defaults")
        defaults.put("workspace", JsonString(nextWorkspace))
        writeRoot(root)
        applyPersistedFieldsToCliConfig()
        nextWorkspace
    }

    public static func setGatewaySettings(settings: GatewayUserSettings): GatewayUserSettings {
        let root = mutableRoot()
        assertGatewayPatchRootIsComplete(root)
        root.put("gateway", settings.toJsonValue())
        let session = cfgEnsureObject(root, "session")
        session.put("dmScope", JsonString(settings.session.dmScope))
        writeRoot(root)
        applyPersistedFieldsToCliConfig()
        settings
    }

    public static func setSkillsEnabled(enabled: Bool): Bool {
        let root = mutableRoot()
        let skills = cfgEnsureObject(root, "skills")
        skills.put("enabled", enabled.toJsonValue())
        writeRoot(root)
        applyPersistedFieldsToCliConfig()
        enabled
    }

    public static func setSkillsEntries(entries: Option<JsonObject>): Option<JsonObject> {
        let root = mutableRoot()
        match (entries) {
            case Some(value) =>
                let skills = cfgEnsureObject(root, "skills")
                skills.put("entries", value)
            case None =>
                match (root.get("skills")) {
                    case Some(rawSkills) =>
                        try {
                            let currentSkills = rawSkills.asObject()
                            let rebuiltSkills = JsonObject()
                            for ((key, value) in currentSkills.getFields()) {
                                if (key == "entries") {
                                    continue
                                }
                                rebuiltSkills.put(key, value)
                            }
                            root.put("skills", rebuiltSkills)
                        } catch (_: Exception) {
                            root.put("skills", JsonObject())
                        }
                    case None => ()
                }
        }
        writeRoot(root)
        applyPersistedFieldsToCliConfig()
        entries
    }

    public static func setMcpServers(servers: Option<JsonObject>): Option<JsonObject> {
        let root = mutableRoot()
        match (servers) {
            case Some(value) => root.put("mcpServers", value)
            case None =>
                match (root.get("mcpServers")) {
                    case Some(_) =>
                        let rebuilt = JsonObject()
                        for ((key, value) in root.getFields()) {
                            if (key == "mcpServers") {
                                continue
                            }
                            rebuilt.put(key, value)
                        }
                        writeRoot(rebuilt)
                        applyPersistedFieldsToCliConfig()
                        return None
                    case None => ()
                }
        }
        writeRoot(root)
        applyPersistedFieldsToCliConfig()
        servers
    }

    public static func setLanguage(language: String): String {
        let normalized = language.trimAscii().toAsciiLower()
        let nextLanguage = if (normalized.isEmpty()) { "unknown" } else { normalized }
        let root = mutableRoot()
        root.put("language", JsonString(nextLanguage))
        writeRoot(root)
        applyPersistedFieldsToCliConfig()
        nextLanguage
    }

    public static func setCollectData(enabled: Bool): Bool {
        let root = mutableRoot()
        root.put("collectData", enabled.toJsonValue())
        writeRoot(root)
        applyPersistedFieldsToCliConfig()
        enabled
    }

    public static func setMemoryBackend(backend: String): String {
        let normalized = backend.trimAscii()
        let nextBackend = if (normalized.isEmpty()) { "local" } else { normalized }
        let root = mutableRoot()
        let memory = cfgEnsureObject(root, "memory")
        memory.put("backend", JsonString(nextBackend))
        writeRoot(root)
        applyPersistedFieldsToCliConfig()
        nextBackend
    }

    public static func setPrimaryModelRef(modelRef: String): String {
        let canonical = canonicalModelRef(modelRef).trimAscii()
        let nextModel = if (canonical.isEmpty()) {
            canonicalModelRef(CliConfig.model).trimAscii()
        } else {
            canonical
        }
        let root = mutableRoot()
        let agents = cfgEnsureObject(root, "agents")
        let defaults = cfgEnsureObject(agents, "defaults")
        let model = cfgEnsureObject(defaults, "model")
        model.put("primary", JsonString(storageModelRef(nextModel)))
        writeRoot(root)
        applyPersistedFieldsToCliConfig()
        nextModel
    }

    public static func setFallbackModelRefs(modelRefs: Array<String>): Array<String> {
        let nextRefs = ArrayList<String>()
        let seen = ArrayList<String>()
        for (raw in modelRefs) {
            let canonical = canonicalModelRef(raw).trimAscii()
            if (!canonical.isEmpty() && !seen.contains(canonical)) {
                seen.add(canonical)
                nextRefs.add(canonical)
            }
        }
        let root = mutableRoot()
        let agents = cfgEnsureObject(root, "agents")
        let defaults = cfgEnsureObject(agents, "defaults")
        let model = cfgEnsureObject(defaults, "model")
        let arr = ArrayList<JsonValue>()
        for (item in nextRefs) {
            arr.add(JsonString(storageModelRef(item)))
        }
        model.put("fallbacks", JsonArray(arr))
        writeRoot(root)
        applyPersistedFieldsToCliConfig()
        nextRefs.toArray()
    }

    public static func setImageModelRef(modelRef: String): String {
        let canonical = canonicalModelRef(modelRef).trimAscii()
        let nextModel = if (canonical.isEmpty()) {
            canonicalModelRef(CliConfig.imageModelOrEmpty()).trimAscii()
        } else {
            canonical
        }
        let root = mutableRoot()
        let agents = cfgEnsureObject(root, "agents")
        let defaults = cfgEnsureObject(agents, "defaults")
        let imageModel = cfgEnsureObject(defaults, "imageModel")
        imageModel.put("primary", JsonString(storageModelRef(nextModel)))
        writeRoot(root)
        applyPersistedFieldsToCliConfig()
        nextModel
    }

    public static func setImageFallbackModelRefs(modelRefs: Array<String>): Array<String> {
        let nextRefs = ArrayList<String>()
        let seen = ArrayList<String>()
        for (raw in modelRefs) {
            let canonical = canonicalModelRef(raw).trimAscii()
            if (!canonical.isEmpty() && !seen.contains(canonical)) {
                seen.add(canonical)
                nextRefs.add(canonical)
            }
        }
        let root = mutableRoot()
        let agents = cfgEnsureObject(root, "agents")
        let defaults = cfgEnsureObject(agents, "defaults")
        let imageModel = cfgEnsureObject(defaults, "imageModel")
        let arr = ArrayList<JsonValue>()
        for (item in nextRefs) {
            arr.add(JsonString(storageModelRef(item)))
        }
        imageModel.put("fallbacks", JsonArray(arr))
        writeRoot(root)
        applyPersistedFieldsToCliConfig()
        nextRefs.toArray()
    }

    public static func setFastModelRef(modelRef: String): String {
        let canonical = canonicalModelRef(modelRef).trimAscii()
        let nextModel = if (canonical.isEmpty()) {
            ""
        } else {
            canonical
        }
        let root = mutableRoot()
        root.put("fastModel", JsonString(storageModelRef(nextModel)))
        writeRoot(root)
        applyPersistedFieldsToCliConfig()
        nextModel
    }

    public static func setTemperature(value: Float64): Float64 {
        let root = mutableRoot()
        root.put("temperature", value.toJsonValue())
        writeRoot(root)
        applyPersistedFieldsToCliConfig()
        value
    }

    public static func setDefaultModelInputLimit(value: Int64): Int64 {
        let root = mutableRoot()
        root.put("defaultModelInputLimit", value.toJsonValue())
        writeRoot(root)
        applyPersistedFieldsToCliConfig()
        value
    }

    public static func setDefaultModelOutputLimit(value: Int64): Int64 {
        let root = mutableRoot()
        root.put("defaultModelOutputLimit", value.toJsonValue())
        writeRoot(root)
        applyPersistedFieldsToCliConfig()
        value
    }

    public static func setProviderApiKey(providerId: String, apiKey: String): String {
        let canonicalProvider = canonicalModelProviderId(providerId)
        let value = apiKey.trimAscii()
        let root = mutableRoot()
        let models = cfgEnsureObject(root, "models")
        let providers = cfgEnsureObject(models, "providers")
        let provider = cfgEnsureObject(providers, canonicalProvider)
        provider.put("apiKey", JsonString(value))

        let auth = cfgEnsureObject(root, "auth")
        let profiles = cfgEnsureObject(auth, "profiles")
        let profile = cfgEnsureObject(profiles, "${canonicalProvider}:default")
        profile.put("provider", JsonString(canonicalProvider))
        profile.put("authMethod", JsonString("api-key"))
        profile.put("apiKey", JsonString(value))
        writeRoot(root)
        applyPersistedFieldsToCliConfig()
        value
    }

    public static func setProviderBaseUrl(providerId: String, baseUrl: String): String {
        let canonicalProvider = canonicalModelProviderId(providerId)
        let value = normalizeConfigPathValue(baseUrl).trimAscii()
        let root = mutableRoot()
        let models = cfgEnsureObject(root, "models")
        let providers = cfgEnsureObject(models, "providers")
        let provider = cfgEnsureObject(providers, canonicalProvider)
        provider.put("baseUrl", JsonString(value))

        let auth = cfgEnsureObject(root, "auth")
        let profiles = cfgEnsureObject(auth, "profiles")
        let profile = cfgEnsureObject(profiles, "${canonicalProvider}:default")
        profile.put("provider", JsonString(canonicalProvider))
        profile.put("authMethod", JsonString("api-key"))
        profile.put("baseUrl", JsonString(value))
        writeRoot(root)
        applyPersistedFieldsToCliConfig()
        value
    }

    public static func setContext7ApiKey(apiKey: String): String {
        let value = apiKey.trimAscii()
        let root = mutableRoot()
        let tools = cfgEnsureObject(root, "tools")
        let context7 = cfgEnsureObject(tools, "context7")
        context7.put("apiKey", JsonString(value))
        writeRoot(root)
        value
    }

    public static func setTavilyApiKey(apiKey: String): String {
        let value = apiKey.trimAscii()
        let root = mutableRoot()
        let tools = cfgEnsureObject(root, "tools")
        let search = cfgEnsureObject(tools, "search")
        let tavily = cfgEnsureObject(search, "tavily")
        tavily.put("apiKey", JsonString(value))
        writeRoot(root)
        value
    }

    public static func writeRoot(root: JsonObject): Unit {
        let path = configPath()
        let persisted = root.toJsonString()
        File.writeTo(path, persisted.toArray())
        _raw = root
        CliSettingManager.invalidate()
        CliModelRuntimeStateManager.writeMaterializedRuntimeState()
        match (_writeRootNotificationHook) {
            case Some(listener) =>
                try {
                    listener(MetisConfigWriteNotification(
                        path.toString(),
                        root,
                        metisConfigStableHash(persisted),
                        DateTime.now().toUnixTimeStamp().toMilliseconds()
                    ))
                } catch (e: Exception) {
                    LogUtils.error("MetisConfigManager.writeRoot notification failed: ${e.message}")
                }
            case None => ()
        }
    }
}
