package metis.program_support

import metis.core.config.{
    MetisConfigManager,
    cliFindModelAuthChoicesForProvider,
    cliModelProviderCatalogDescriptors,
    cliProviderApiKeyConfigPath,
    cliProviderBaseUrlConfigPath
}

import std.collection.ArrayList
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString, JsonValue}

public func programSupportBuildProviderCatalog(): JsonArray {
    let rows = ArrayList<JsonValue>()
    for (preset in cliModelProviderCatalogDescriptors()) {
        let row = JsonObject()
        row.put("provider", JsonString(preset.providerId))
        row.put("displayName", JsonString(preset.displayName))
        row.put("groupId", JsonString(preset.groupId))
        row.put("runtimeProvider", JsonString(preset.runtimeProviderId))
        row.put("apiKeyConfigPath", JsonString(cliProviderApiKeyConfigPath(preset.providerId)))
        row.put("baseUrlConfigPath", JsonString(cliProviderBaseUrlConfigPath(preset.providerId)))
        row.put("defaultModelRef", JsonString(preset.defaultModelRef))
        let baseUrl = MetisConfigManager.readProviderBaseUrl(preset.providerId)
        row.put("baseUrl", JsonString(if (baseUrl.isEmpty()) { preset.defaultBaseUrl } else { baseUrl }))
        row.put("configured", JsonBool(!(MetisConfigManager.readProviderApiKey(preset.providerId).isEmpty())))
        row.put("highPriority", JsonBool(preset.highPriority))
        let aliases = ArrayList<JsonValue>()
        for (alias in preset.aliases) {
            aliases.add(JsonString(alias))
        }
        row.put("aliases", JsonArray(aliases))
        let authChoices = ArrayList<JsonValue>()
        for (choice in cliFindModelAuthChoicesForProvider(preset.providerId)) {
            let authRow = JsonObject()
            authRow.put("choiceId", JsonString(choice.choiceId))
            authRow.put("label", JsonString(choice.label))
            authRow.put("authMethod", JsonString(choice.authMethod))
            authRow.put("defaultModelRef", JsonString(choice.defaultModelRef))
            authChoices.add(authRow)
        }
        row.put("authChoices", JsonArray(authChoices))
        row.put("docsUrl", JsonString(preset.docsUrl))
        rows.add(row)
    }
    JsonArray(rows)
}
