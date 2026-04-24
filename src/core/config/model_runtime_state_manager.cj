package metis.core.config

import magic.jsonable.*
import magic.log.LogUtils

import std.collection.ArrayList
import std.fs.{File, exists, Path}
import stdx.encoding.json.{JsonArray, JsonInt, JsonObject, JsonString, JsonValue}

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

public class CliModelRuntimeStateManager {
    public static func runtimePath(): Path {
        MetisPaths.modelsRuntimePath()
    }

    public static func writeMaterializedRuntimeState(): Unit {
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

        File.writeTo(runtimePath(), root.toJsonString().toArray())
    }

    public static func readRuntimeState(): Option<JsonObject> {
        let path = runtimePath()
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
