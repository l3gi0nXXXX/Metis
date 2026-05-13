package metis.core.config

import magic.jsonable.*
import magic.log.LogUtils

import std.collection.ArrayList
import std.fs.{Directory, File, exists, Path}
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private const RUNTIME_STATE_GENERATED_BY = "metis"
private const RUNTIME_STATE_MATERIALIZED_SOURCE = "agent-scope"

private func runtimeStateGetString(root: JsonObject, key: String): Option<String> {
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

private func runtimeStateGetObject(root: JsonObject, key: String): Option<JsonObject> {
    match (root.get(key)) {
        case Some(value) =>
            try {
                Some(value.asObject())
            } catch (_: Exception) {
                None
            }
        case None => None
    }
}

private func runtimeStateGetBool(root: JsonObject, key: String): Option<Bool> {
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

private func runtimeStateGetArray(root: JsonObject, key: String): JsonArray {
    match (root.get(key)) {
        case Some(value) =>
            try {
                value.asArray()
            } catch (_: Exception) {
                JsonArray(Array<JsonValue>())
            }
        case None => JsonArray(Array<JsonValue>())
    }
}

private func runtimeStateStringArray(items: JsonArray): Array<String> {
    let out = ArrayList<String>()
    for (item in items.getItems()) {
        try {
            let text = item.asString().getValue().trimAscii()
            if (!text.isEmpty()) {
                out.add(text)
            }
        } catch (_: Exception) {
            ()
        }
    }
    out.toArray()
}

private func runtimeStateScopeModel(scope: JsonObject): JsonObject {
    match (runtimeStateGetObject(scope, "model")) {
        case Some(model) => model
        case None => JsonObject()
    }
}

private func runtimeStateScopePrimary(scope: JsonObject): String {
    let scoped = runtimeStateGetString(scope, "modelRef").getOrDefault { "" }.trimAscii()
    if (!scoped.isEmpty()) {
        return scoped
    }
    let model = runtimeStateScopeModel(scope)
    let modelRef = runtimeStateGetString(model, "modelRef").getOrDefault { "" }.trimAscii()
    if (!modelRef.isEmpty()) {
        return modelRef
    }
    runtimeStateGetString(model, "primary").getOrDefault { "" }.trimAscii()
}

private func runtimeStateScopeFallbacksConfigured(scope: JsonObject): Bool {
    let model = runtimeStateScopeModel(scope)
    match (model.get("fallbacks")) {
        case Some(_) => true
        case None => false
    }
}

private func runtimeStateScopeFallbacks(scope: JsonObject): Array<String> {
    let model = runtimeStateScopeModel(scope)
    runtimeStateStringArray(runtimeStateGetArray(model, "fallbacks"))
}

private func currentCliPrimaryModel(): String {
    try {
        CliConfig.model.trimAscii()
    } catch (_: Exception) {
        ""
    }
}

private func currentCliFastModel(): String {
    match (CliConfig.fastModel) {
        case Some(model) => model.trimAscii()
        case None => ""
    }
}

private func normalizeModelArray(models: Array<String>): Array<String> {
    let out = ArrayList<String>()
    for (model in models) {
        let normalized = MetisConfigManager.normalizeModelRef(model).trimAscii()
        if (!normalized.isEmpty()) {
            out.add(normalized)
        }
    }
    out.toArray()
}

private func currentCliFallbackModels(): Array<String> {
    normalizeModelArray(CliConfig.fallbackModels)
}

private func canonicalModelArray(models: Array<String>): Array<String> {
    let out = ArrayList<String>()
    for (model in models) {
        let canonical = MetisConfigManager.canonicalModelRef(model).trimAscii()
        if (!canonical.isEmpty()) {
            out.add(canonical)
        }
    }
    out.toArray()
}

private func jsonArrayFromStrings(items: Array<String>): JsonArray {
    let out = ArrayList<JsonValue>()
    for (item in items) {
        out.add(JsonString(item))
    }
    JsonArray(out)
}

private func runtimeStateScopeFingerprint(scope: JsonObject): String {
    let agentId = runtimeStateGetString(scope, "agentId").getOrDefault { "" }.trimAscii()
    let primary = MetisConfigManager.normalizeModelRef(runtimeStateScopePrimary(scope)).trimAscii()
    let fallbackConfigured = runtimeStateScopeFallbacksConfigured(scope)
    let fallbacks = normalizeModelArray(runtimeStateScopeFallbacks(scope))
    "agentId=${agentId};primary=${primary};fallbacksConfigured=${fallbackConfigured};fallbacks=${String.join(fallbacks, delimiter: ",")}"
}

private func runtimeStateMarkGeneratedForScope(root: JsonObject, scope: JsonObject): JsonObject {
    root.put("generated", true.toJsonValue())
    root.put("generatedBy", JsonString(RUNTIME_STATE_GENERATED_BY))
    root.put("materializedSource", JsonString(RUNTIME_STATE_MATERIALIZED_SOURCE))
    root.put("scopeFingerprint", JsonString(runtimeStateScopeFingerprint(scope)))
    root
}

private func runtimeStateIsGenerated(root: JsonObject): Bool {
    (runtimeStateGetBool(root, "generated").getOrDefault { false }) &&
        runtimeStateGetString(root, "generatedBy").getOrDefault { "" }.trimAscii() == RUNTIME_STATE_GENERATED_BY &&
        runtimeStateGetString(root, "materializedSource").getOrDefault { "" }.trimAscii() == RUNTIME_STATE_MATERIALIZED_SOURCE
}

public class CliModelRuntimeStateRefreshResult {
    public var status: String = ""
    public var reason: String = ""
    public var path: String = ""
    public var refreshed: Bool = false
    public init() {}
}

public class CliModelRuntimeStateManager {
    public static func runtimePath(): Path {
        MetisPaths.modelsRuntimePath()
    }

    private static func buildMaterializedRuntimeState(): JsonObject {
        let primaryRuntime = MetisConfigManager.normalizeModelRef(
            MetisConfigManager.readPrimaryModel() ?? currentCliPrimaryModel()
        ).trimAscii()
        let canonicalPrimary = MetisConfigManager.canonicalModelRef(primaryRuntime).trimAscii()

        let fastRuntime = MetisConfigManager.normalizeModelRef(currentCliFastModel()).trimAscii()
        let canonicalFast = MetisConfigManager.canonicalModelRef(fastRuntime).trimAscii()

        let fallbackRuntime = if (MetisConfigManager.readFallbackModels().isEmpty()) {
            currentCliFallbackModels()
        } else {
            MetisConfigManager.readFallbackModels()
        }
        let canonicalFallbacks = canonicalModelArray(fallbackRuntime)

        let root = JsonObject()
        root.put("primaryModelRef", JsonString(canonicalPrimary))
        root.put("runtimePrimaryModelRef", JsonString(primaryRuntime))
        root.put("fastModelRef", JsonString(canonicalFast))
        root.put("runtimeFastModelRef", JsonString(fastRuntime))
        root.put("fallbackModelRefs", jsonArrayFromStrings(canonicalFallbacks))
        root.put("runtimeFallbackModelRefs", jsonArrayFromStrings(fallbackRuntime))
        root.put("defaultInputLimit", CliConfig.defaultModelInputLimit.toJsonValue())
        root.put("defaultOutputLimit", CliConfig.defaultModelOutputLimit.toJsonValue())

        let providers = ArrayList<JsonValue>()
        for (descriptor in cliModelProviderCatalogDescriptors()) {
            let row = JsonObject()
            row.put("provider", JsonString(descriptor.providerId))
            row.put("runtimeProvider", JsonString(descriptor.runtimeProviderId))
            row.put("displayName", JsonString(descriptor.displayName))
            row.put("groupId", JsonString(descriptor.groupId))
            row.put("defaultModelRef", JsonString(descriptor.defaultModelRef))
            row.put("configured", (!MetisConfigManager.readProviderApiKey(descriptor.providerId).trimAscii().isEmpty()).toJsonValue())
            row.put("apiKeyConfigPath", JsonString(cliProviderApiKeyConfigPath(descriptor.providerId)))
            row.put("baseUrlConfigPath", JsonString(cliProviderBaseUrlConfigPath(descriptor.providerId)))
            let baseUrl = MetisConfigManager.readProviderBaseUrl(descriptor.providerId).trimAscii()
            row.put("baseUrl", JsonString(if (baseUrl.isEmpty()) { descriptor.defaultBaseUrl } else { baseUrl }))
            providers.add(row)
        }
        root.put("providers", JsonArray(providers))
        root
    }

    private static func buildMaterializedRuntimeStateForScope(scope: JsonObject): JsonObject {
        let root = buildMaterializedRuntimeState()
        let scopedPrimary = MetisConfigManager.normalizeModelRef(runtimeStateScopePrimary(scope)).trimAscii()
        if (!scopedPrimary.isEmpty()) {
            root.put("primaryModelRef", JsonString(MetisConfigManager.canonicalModelRef(scopedPrimary).trimAscii()))
            root.put("runtimePrimaryModelRef", JsonString(scopedPrimary))
        }
        if (runtimeStateScopeFallbacksConfigured(scope)) {
            let scopedFallbacks = normalizeModelArray(runtimeStateScopeFallbacks(scope))
            root.put("fallbackModelRefs", jsonArrayFromStrings(canonicalModelArray(scopedFallbacks)))
            root.put("runtimeFallbackModelRefs", jsonArrayFromStrings(scopedFallbacks))
        }
        match (runtimeStateGetObject(scope, "credentialSource")) {
            case Some(source) => root.put("credentialSource", source)
            case None =>
                match (runtimeStateGetObject(scope, "accountSummary")) {
                    case Some(source) => root.put("credentialSource", source)
                    case None => ()
                }
        }
        runtimeStateMarkGeneratedForScope(root, scope)
    }

    private static func writeRuntimeStateTo(path: Path, root: JsonObject): Unit {
        let parent = path.parent
        if (!exists(parent)) {
            Directory.create(parent, recursive: true)
        }
        File.writeTo(path, root.toJsonString().toArray())
    }

    private static func writeMaterializedRuntimeStateTo(path: Path): Unit {
        writeRuntimeStateTo(path, buildMaterializedRuntimeState())
    }

    public static func writeMaterializedRuntimeState(): Unit {
        writeMaterializedRuntimeStateTo(runtimePath())
    }

    public static func agentRuntimePath(agentDir: Path): Path {
        agentDir.join("models.json")
    }

    public static func ensureAgentRuntimeState(agentDir: Path): Path {
        let path = agentRuntimePath(agentDir)
        if (!exists(path)) {
            writeMaterializedRuntimeStateTo(path)
        }
        path
    }

    public static func ensureAgentRuntimeStateForScope(agentDir: Path, scope: JsonObject): Path {
        let path = agentRuntimePath(agentDir)
        if (!exists(path)) {
            writeRuntimeStateTo(path, buildMaterializedRuntimeStateForScope(scope))
        }
        path
    }

    public static func refreshAgentRuntimeStateForScope(agentDir: Path, scope: JsonObject): CliModelRuntimeStateRefreshResult {
        let result = CliModelRuntimeStateRefreshResult()
        let path = agentRuntimePath(agentDir)
        result.path = path.toString()
        if (!exists(path)) {
            writeRuntimeStateTo(path, buildMaterializedRuntimeStateForScope(scope))
            result.status = "created"
            result.reason = "missing-runtime-state"
            result.refreshed = true
            return result
        }
        match (readRuntimeStateFrom(path)) {
            case Some(current) =>
                if (runtimeStateIsGenerated(current)) {
                    writeRuntimeStateTo(path, buildMaterializedRuntimeStateForScope(scope))
                    result.status = "refreshed"
                    result.reason = "generated-runtime-state"
                    result.refreshed = true
                } else {
                    result.status = "skipped"
                    result.reason = "manual-runtime-state"
                }
            case None =>
                result.status = "skipped"
                result.reason = "invalid-runtime-state"
        }
        result
    }

    public static func readRuntimeState(): Option<JsonObject> {
        readRuntimeStateFrom(runtimePath())
    }

    public static func readRuntimeStateFrom(path: Path): Option<JsonObject> {
        if (!exists(path)) {
            return None
        }
        try {
            Some(JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject())
        } catch (e: Exception) {
            LogUtils.error("Failed to read models runtime state: ${e.message}")
            None
        }
    }

    public static func applyRuntimeStateToCliConfig(): Unit {
        match (readRuntimeState()) {
            case Some(root) =>
                match (runtimeStateGetString(root, "runtimePrimaryModelRef")) {
                    case Some(model) =>
                        let trimmed = model.trimAscii()
                        if (!trimmed.isEmpty()) {
                            CliConfig.model = trimmed
                        }
                    case None => ()
                }
                match (runtimeStateGetString(root, "runtimeFastModelRef")) {
                    case Some(model) =>
                        let trimmed = model.trimAscii()
                        if (!trimmed.isEmpty()) {
                            CliConfig.fastModel = Some(trimmed)
                        }
                    case None => ()
                }
                let runtimeFallbacks = runtimeStateGetArray(root, "runtimeFallbackModelRefs")
                let nextFallbacks = ArrayList<String>()
                for (item in runtimeFallbacks.getItems()) {
                    try {
                        let text = item.asString().getValue().trimAscii()
                        if (!text.isEmpty()) {
                            nextFallbacks.add(text)
                        }
                    } catch (_: Exception) {
                        ()
                    }
                }
                if (nextFallbacks.size > 0) {
                    CliConfig.fallbackModels = nextFallbacks.toArray()
                }
                match (root.get("defaultInputLimit")) {
                    case Some(value) =>
                        try {
                            CliConfig.defaultModelInputLimit = value.asInt().getValue()
                        } catch (_: Exception) {
                            ()
                        }
                    case None => ()
                }
                match (root.get("defaultOutputLimit")) {
                    case Some(value) =>
                        try {
                            CliConfig.defaultModelOutputLimit = value.asInt().getValue()
                        } catch (_: Exception) {
                            ()
                        }
                    case None => ()
                }
            case None => ()
        }
    }
}
