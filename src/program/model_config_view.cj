package metis.program
import magic.jsonable.*

import metis.core.model.CliModelManager
import metis.core.config.{CliConfig, MetisConfigManager, CliModelRuntimeStateManager, cliFindModelAuthChoicesForProvider, cliFindModelProviderDescriptor,
    cliModelAuthChoiceCatalog, cliModelAuthChoiceGroups, cliModelProviderCatalogDescriptors, cliProviderApiKeyConfigPath, cliProviderBaseUrlConfigPath}
import metis.program_support.programSupportBuildProviderCatalog

import std.collection.ArrayList
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString, JsonValue}

private func cliResolveConfigProviderId(providerId: String, modelId: String): String {
    let normalizedProvider = providerId.trimAscii().toAsciiLower()
    if (normalizedProvider.isEmpty()) {
        return normalizedProvider
    }
    if (normalizedProvider == "ark") {
        let normalizedModel = modelId.trimAscii().toAsciiLower()
        if (normalizedModel.startsWith("qwen") || normalizedModel.startsWith("qwq")) {
            return "qwen"
        }
        return "volcengine"
    }
    if (normalizedProvider == "zhipuai" || normalizedProvider == "glm") {
        return "zai"
    }
    normalizedProvider
}

public func cliCurrentModelRef(): String {
    try {
        MetisConfigManager.canonicalModelRef(CliConfig.model.trimAscii())
    } catch (_ : Exception) {
        "ark:kimi-k2-250905"
    }
}

public func cliCurrentProviderId(): String {
    let model = cliCurrentModelRef()
    if (let Some(index) <- model.indexOf(":")) {
        return model[..index].trimAscii().toAsciiLower()
    }
    "ark"
}

public func cliCurrentModelId(): String {
    let model = cliCurrentModelRef()
    if (let Some(index) <- model.indexOf(":")) {
        return model[(index + 1)..].trimAscii()
    }
    model
}

public func cliCurrentApiKeyConfigPath(): String {
    cliProviderApiKeyConfigPath(cliResolveConfigProviderId(cliCurrentProviderId(), cliCurrentModelId()))
}

public func cliCurrentBaseUrlConfigPath(): String {
    cliProviderBaseUrlConfigPath(cliResolveConfigProviderId(cliCurrentProviderId(), cliCurrentModelId()))
}

public func cliCurrentBaseUrl(): String {
    match (cliFindModelProviderDescriptor(cliResolveConfigProviderId(cliCurrentProviderId(), cliCurrentModelId()))) {
        case Some(preset) =>
            let current = MetisConfigManager.readProviderBaseUrl(preset.providerId)
            if (current.isEmpty()) {
                preset.defaultBaseUrl
            } else {
                current
            }
        case None => ""
    }
}

public func cliCurrentProviderConfigured(): Bool {
    let providerId = cliResolveConfigProviderId(cliCurrentProviderId(), cliCurrentModelId())
    if (providerId.isEmpty()) {
        return false
    }
    !(MetisConfigManager.readProviderApiKey(providerId).isEmpty())
}

public func cliFastModelRef(): String {
    match (CliConfig.fastModel) {
        case Some(model) => model.trimAscii()
        case None => ""
    }
}

public func cliFallbackModelJson(): JsonArray {
    let rows = ArrayList<JsonValue>()
    for (model in CliConfig.fallbackModels) {
        let trimmed = model.trimAscii()
        if (!trimmed.isEmpty()) {
            rows.add(JsonString(trimmed))
        }
    }
    JsonArray(rows)
}

public func cliImageFallbackModelJson(): JsonArray {
    let rows = ArrayList<JsonValue>()
    for (model in CliConfig.imageFallbackModels) {
        let trimmed = model.trimAscii()
        if (!trimmed.isEmpty()) {
            rows.add(JsonString(trimmed))
        }
    }
    JsonArray(rows)
}

public func cliBuildCurrentModelConfigView(): JsonObject {
    let obj = JsonObject()
    let providerId = cliCurrentProviderId()
    obj.put("provider", JsonString(providerId))
    obj.put("configProvider", JsonString(cliResolveConfigProviderId(providerId, cliCurrentModelId())))
    obj.put("model", JsonString(cliCurrentModelId()))
    obj.put("modelRef", JsonString(cliCurrentModelRef()))
    obj.put("apiKeyConfigPath", JsonString(cliCurrentApiKeyConfigPath()))
    obj.put("baseUrlConfigPath", JsonString(cliCurrentBaseUrlConfigPath()))
    obj.put("baseUrl", JsonString(cliCurrentBaseUrl()))
    obj.put("configured", JsonBool(cliCurrentProviderConfigured()))
    match (cliFindModelProviderDescriptor(providerId)) {
        case Some(preset) =>
            obj.put("runtimeProvider", JsonString(preset.runtimeProviderId))
            obj.put("displayName", JsonString(preset.displayName))
            obj.put("groupId", JsonString(preset.groupId))
            obj.put("defaultModelRef", JsonString(preset.defaultModelRef))
        case None =>
            obj.put("runtimeProvider", JsonString(providerId))
    }
    obj.put("fastModel", JsonString(cliFastModelRef()))
    obj.put("fallbackModels", cliFallbackModelJson())
    obj.put("imageModelRef", JsonString(CliConfig.imageModelOrEmpty()))
    obj.put("imageFallbackModels", cliImageFallbackModelJson())
    obj.put("defaultInputLimit", CliConfig.defaultModelInputLimit.toJsonValue())
    obj.put("defaultOutputLimit", CliConfig.defaultModelOutputLimit.toJsonValue())
    obj
}

public func cliBuildModelRuntimeStateView(): JsonObject {
    let obj = JsonObject()
    obj.put("path", JsonString(CliModelRuntimeStateManager.runtimePath().toString()))
    match (CliModelRuntimeStateManager.readRuntimeState()) {
        case Some(root) =>
            obj.put("exists", JsonBool(true))
            obj.put("primaryModelRef", root.get("primaryModelRef").getOrDefault { => JsonString("") })
            obj.put("runtimePrimaryModelRef", root.get("runtimePrimaryModelRef").getOrDefault { => JsonString("") })
            obj.put("fastModelRef", root.get("fastModelRef").getOrDefault { => JsonString("") })
            obj.put("runtimeFastModelRef", root.get("runtimeFastModelRef").getOrDefault { => JsonString("") })
            obj.put("fallbackModelRefs", root.get("fallbackModelRefs").getOrDefault { => JsonArray(Array<JsonValue>()) })
            obj.put("runtimeFallbackModelRefs", root.get("runtimeFallbackModelRefs").getOrDefault { => JsonArray(Array<JsonValue>()) })
            obj.put("providers", root.get("providers").getOrDefault { => JsonArray(Array<JsonValue>()) })
        case None =>
            obj.put("exists", JsonBool(false))
    }
    obj
}

public func cliBuildModelSelectionView(): JsonObject {
    let obj = JsonObject()
    let candidates = ArrayList<JsonValue>()
    for (model in CliModelManager.modelSelectionSummary()) {
        candidates.add(JsonString(model))
    }
    obj.put("current", JsonString(cliCurrentModelRef()))
    obj.put("runtimeCurrent", JsonString(try { CliConfig.model } catch (_: Exception) { "" }))
    obj.put("fastModel", JsonString(cliFastModelRef()))
    obj.put("fallbackModels", cliFallbackModelJson())
    obj.put("candidateModels", JsonArray(candidates))
    obj
}

public func cliBuildModelAuthChoiceCatalog(): JsonArray {
    let rows = ArrayList<JsonValue>()
    for (choice in cliModelAuthChoiceCatalog()) {
        let row = JsonObject()
        row.put("choiceId", JsonString(choice.choiceId))
        row.put("provider", JsonString(choice.providerId))
        row.put("groupId", JsonString(choice.groupId))
        row.put("label", JsonString(choice.label))
        row.put("authMethod", JsonString(choice.authMethod))
        row.put("defaultModelRef", JsonString(choice.defaultModelRef))
        row.put("docsUrl", JsonString(choice.docsUrl))
        row.put("highPriority", JsonBool(choice.highPriority))
        rows.add(row)
    }
    JsonArray(rows)
}

public func cliBuildModelAuthChoiceGroups(): JsonArray {
    let rows = ArrayList<JsonValue>()
    for (group in cliModelAuthChoiceGroups()) {
        let row = JsonObject()
        row.put("groupId", JsonString(group.groupId))
        row.put("title", JsonString(group.title))
        row.put("description", JsonString(group.description))
        rows.add(row)
    }
    JsonArray(rows)
}

public func cliBuildProviderCatalog(): JsonArray {
    programSupportBuildProviderCatalog()
}
