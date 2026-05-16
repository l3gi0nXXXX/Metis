package metis.cliapp

import metis.core.config.{CliConfig, MetisConfigManager}
import metis.core.model.CliModelManager
import metis.io.{InputUtils, PrintUtils, WithColor, Theme, AnsiColor}
import metis.program_support.{
    CliModelProviderPreset,
    programSupportIsModelsCommandLine,
    programSupportIsModelsPageToken,
    programSupportModelProviderPresets,
    programSupportParseModelsPage,
    programSupportRenderModelsHelp,
    programSupportRenderModelsProviderIndex,
    programSupportRenderModelsProviderModels,
    programSupportRenderModelsStatus
}

import std.collection.{ArrayList, filter, map, collectArray}

protected func modelProviderPresets(): Array<CliModelProviderPreset> {
    programSupportModelProviderPresets()
}

protected func handleModelsCommand(app: CliApp): Unit {
    let presets = modelProviderPresets()
    PrintUtils.printProcedure("Models", "Configure provider credentials and main model")
    PrintUtils.printLine("${"Current model:".withColor(Theme.MUTED)} ${CliConfig.model.withColor(Theme.ACCENT).withColor(AnsiColor.BOLD)}")
    let tipsLine = "${"Tips:".withColor(Theme.MUTED)} Enter keeps default. Press ${"ESC".withColor(Theme.HIGHLIGHT)} to cancel and return to chat."
    PrintUtils.printLine(tipsLine)
    PrintUtils.printLine("")

    let providerOptions = presets |>
        map { preset =>
            let key = MetisConfigManager.readProviderApiKey(preset.configProvider)
            let apiKeyStatus = if (key.trimAscii().isEmpty()) {
                "API KEY: not set"
            } else {
                "API KEY: configured"
            }
            "${preset.name} | ${apiKeyStatus}"
        } |>
        collectArray

    let providerIndex = InputUtils.getOptions(providerOptions, prompt: "Select provider (Enter to confirm, ESC to cancel)")
    let preset = match (providerIndex) {
        case Some(index) => presets[index]
        case None =>
            PrintUtils.printLine("Cancelled /models.")
            return
    }

    let defaultModelId = getDefaultModelId(preset, CliConfig.model)
    let modelPrompt = if (defaultModelId.isEmpty()) {
        "Model ID (${preset.name}) [required, e.g. ${String.join(preset.suggestedModels, delimiter: ", ")}]:"
    } else {
        "Model ID (${preset.name}) [default: ${defaultModelId}]:"
    }
    var modelInput = match (InputUtils.getUserInputOrCancel(prompt: modelPrompt)) {
        case Some(text) => text.trimAscii()
        case None =>
            PrintUtils.printLine("Cancelled /models.")
            return
    }
    if (modelInput.isEmpty()) {
        modelInput = defaultModelId
    }
    modelInput = normalizeModelId(modelInput)
    if (modelInput.isEmpty()) {
        PrintUtils.printLine("Model is empty, cancelled.")
        return
    }
    let mainModel = "${preset.modelProvider}:${modelInput}"

    let oldApiKey = MetisConfigManager.readProviderApiKey(preset.configProvider).trimAscii()
    let apiKeyPrompt = if (oldApiKey.isEmpty()) {
        "API key [required, stored at ${preset.apiKeyConfigPath}]:"
    } else {
        "API key [default: keep current at ${preset.apiKeyConfigPath}]:"
    }
    var apiKey = match (InputUtils.getUserInputOrCancel(prompt: apiKeyPrompt)) {
        case Some(text) => text.trimAscii()
        case None =>
            PrintUtils.printLine("Cancelled /models.")
            return
    }
    if (apiKey.isEmpty()) {
        apiKey = oldApiKey
    }
    if (apiKey.isEmpty()) {
        PrintUtils.printLine("API key is empty, cancelled.")
        return
    }

    let configuredBaseURL = MetisConfigManager.readProviderBaseUrl(preset.configProvider).trimAscii()
    let oldBaseURL = if (!configuredBaseURL.isEmpty()) { configuredBaseURL } else { preset.defaultBaseURL.trimAscii() }
    let baseURLPrompt = "Base URL [default: ${oldBaseURL}, stored at ${preset.baseURLConfigPath}]:"
    let baseURLInput = match (InputUtils.getUserInputOrCancel(prompt: baseURLPrompt)) {
        case Some(text) => text.trimAscii()
        case None =>
            PrintUtils.printLine("Cancelled /models.")
            return
    }
    let baseURL = if (baseURLInput.isEmpty()) { oldBaseURL } else { baseURLInput }

    PrintUtils.printLine("")
    PrintUtils.printLine("Will apply:".withColor(Theme.PRIMARY).withColor(AnsiColor.BOLD))
    PrintUtils.printLine("  ${"provider:".withColor(Theme.MUTED)} ${preset.modelProvider.withColor(Theme.INFO)}")
    PrintUtils.printLine("  ${"model:".withColor(Theme.MUTED)} ${mainModel.withColor(Theme.ACCENT)}")
    PrintUtils.printLine("  ${"API KEY:".withColor(Theme.MUTED)} ${maskSecret(apiKey).withColor(Theme.INFO)}")
    PrintUtils.printLine("  ${"Base URL:".withColor(Theme.MUTED)} ${baseURL.withColor(Theme.INFO)}")
    PrintUtils.printLine("")

    let apply = InputUtils.getOptions(["Save and apply now", "Cancel"], prompt: "Confirm /models")
    match (apply) {
        case Some(0) => ()
        case _ =>
            PrintUtils.printLine("Cancelled /models.")
            return
    }

    // Persist model selection through the root config patch path so gateway
    // and other unrelated config sections are preserved.
    let savedModel = !MetisConfigManager.setPrimaryModelRef(mainModel).trimAscii().isEmpty()

    // Persist provider credentials into metis.json.
    let savedApiKey = !MetisConfigManager.setProviderApiKey(preset.configProvider, apiKey).trimAscii().isEmpty()
    let savedBaseUrl = !MetisConfigManager.setProviderBaseUrl(preset.configProvider, baseURL).trimAscii().isEmpty()
    let savedProvider = savedApiKey && savedBaseUrl

    // Reset model caches and apply the new main model immediately
    CliModelManager.resetRuntimeState()
    app.agent.model = CliModelManager.model

    if (savedModel && savedProvider) {
        PrintUtils.printLine("Model configuration updated. Current model: ${CliConfig.model}")
    } else if (savedModel && !savedProvider) {
        PrintUtils.printLine("Model updated, but failed to persist provider credentials to metis.json.")
    } else {
        PrintUtils.printLine("Model switched for current session, but failed to save settings.")
    }
}

protected func isModelsCommandLine(raw: String): Bool {
    programSupportIsModelsCommandLine(raw)
}

protected func handleModelsCommandLine(app: CliApp, raw: String): Unit {
    let tokens = raw.trimAscii().split(" ") |>
        filter { x => !x.trimAscii().isEmpty() } |>
        map { x => x.trimAscii() } |>
        collectArray
    if (tokens.size <= 1) {
        handleModelsCommand(app)
        return
    }
    let sub = tokens[1].toAsciiLower()
    if (sub == "help" || sub == "-h" || sub == "--help") {
        PrintUtils.printLine(renderModelsHelp())
        return
    }
    if (sub == "status") {
        PrintUtils.printLine(renderModelsStatus())
        return
    }
    if (sub == "set-image") {
        if (tokens.size < 3) {
            PrintUtils.printLine("Usage: /models set-image <provider:model>")
            return
        }
        let applied = MetisConfigManager.setImageModelRef(tokens[2])
        PrintUtils.printLine("Image understanding model updated: ${applied}")
        return
    }
    if (sub == "image-fallbacks") {
        if (tokens.size < 3) {
            PrintUtils.printLine("Usage: /models image-fallbacks add|remove|clear <provider:model>")
            return
        }
        let action = tokens[2].toAsciiLower()
        let current = ArrayList<String>()
        for (item in MetisConfigManager.readImageFallbackModels()) {
            if (!item.trimAscii().isEmpty() && !current.contains(item.trimAscii())) {
                current.add(item.trimAscii())
            }
        }
        if (action == "clear") {
            let applied = MetisConfigManager.setImageFallbackModelRefs([])
            PrintUtils.printLine("Image understanding fallbacks cleared (${applied.size}).")
            return
        }
        if (tokens.size < 4) {
            PrintUtils.printLine("Usage: /models image-fallbacks ${action} <provider:model>")
            return
        }
        let canonical = MetisConfigManager.canonicalModelRef(tokens[3]).trimAscii()
        if (action == "add") {
            if (!canonical.isEmpty() && !current.contains(canonical)) {
                current.add(canonical)
            }
        } else if (action == "remove") {
            let kept = ArrayList<String>()
            for (item in current) {
                if (item != canonical) {
                    kept.add(item)
                }
            }
            current.clear()
            for (item in kept) {
                current.add(item)
            }
        } else {
            PrintUtils.printLine("Usage: /models image-fallbacks add|remove|clear <provider:model>")
            return
        }
        let applied = MetisConfigManager.setImageFallbackModelRefs(current.toArray())
        PrintUtils.printLine("Image understanding fallbacks: ${String.join(applied, delimiter: ", ")}")
        return
    }
    if (isModelsPageToken(sub)) {
        PrintUtils.printLine(renderModelsProviderIndex(parseModelsPage(sub)))
        return
    }
    let page = if (tokens.size >= 3) { parseModelsPage(tokens[2]) } else { 1 }
    PrintUtils.printLine(renderModelsProviderModels(tokens[1], page))
}

protected func renderModelsHelp(): String {
    programSupportRenderModelsHelp()
}

protected func renderModelsStatus(): String {
    programSupportRenderModelsStatus()
}

protected func renderModelsProviderIndex(page: Int64): String {
    programSupportRenderModelsProviderIndex(page)
}

protected func renderModelsProviderModels(provider: String, page: Int64): String {
    programSupportRenderModelsProviderModels(provider, page)
}

private func isModelsPageToken(value: String): Bool {
    programSupportIsModelsPageToken(value)
}

private func parseModelsPage(value: String): Int64 {
    programSupportParseModelsPage(value)
}

private func getDefaultModelId(preset: CliModelProviderPreset, currentModel: String): String {
    let prefix = "${preset.modelProvider}:"
    if (currentModel.startsWith(prefix) && currentModel.size > prefix.size) {
        return currentModel[prefix.size..].trimAscii()
    }
    if (!preset.suggestedModels.isEmpty()) {
        return preset.suggestedModels[0]
    }
    return ""
}

private func normalizeModelId(modelInput: String): String {
    let content = modelInput.trimAscii()
    if (content.isEmpty()) {
        return ""
    }
    if (let Some(index) <- content.indexOf(b':')) {
        return content[index + 1..].trimAscii()
    }
    return content
}

private func maskSecret(secret: String): String {
    if (secret.size <= 8) {
        return "********"
    }
    return "${secret[0..4]}****${secret[secret.size - 4..]}"
}

