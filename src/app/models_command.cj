package metis.app

import metis.core.config.CliConfig
import metis.core.config.MetisConfigManager
import metis.core.model.CliModelManager
import metis.io.{InputUtils, PrintUtils, WithColor, Theme, AnsiColor}

import std.collection.{map, collectArray}

protected struct ModelProviderPreset {
    ModelProviderPreset(
        let modelProvider: String,
        let configProvider: String,
        let name: String,
        let apiKeyConfigPath: String,
        let baseURLConfigPath: String,
        let defaultBaseURL: String,
        let suggestedModels: Array<String>
    ) { }
}

protected func modelProviderPresets(): Array<ModelProviderPreset> {
    [
    ModelProviderPreset(
        "ark",
        "volcengine",
        "Volcano ARK Coding Plan",
        "models.providers.volcengine.apiKey",
        "models.providers.volcengine.baseUrl",
        "https://ark.cn-beijing.volces.com/api/coding/v3",
        ["ark-code-latest", "kimi-k2-250905"]
    ),
    ModelProviderPreset(
        "moonshot",
        "moonshot",
        "Kimi Code",
        "models.providers.moonshot.apiKey",
        "models.providers.moonshot.baseUrl",
        "https://api.kimi.com/coding/v1",
        ["kimi-for-coding", "kimi-k2-0711-preview"]
    ),
    ModelProviderPreset(
        "zhipuai",
        "zai",
        "GLM Coding Plan",
        "models.providers.zai.apiKey",
        "models.providers.zai.baseUrl",
        "https://open.bigmodel.cn/api/coding/paas/v4",
        ["glm-4.7", "glm-4.5"]
    ),
    // ModelProviderPreset(
    //     "openai",
    //     "NVIDIA NIM",
    //     "NVIDIA_NIM_API_KEY",
    //     "NVIDIA_NIM_BASE_URL",
    //     "https://integrate.api.nvidia.com/v1/",
    //     ["minimaxai/minimax-m2.1", "z-ai/glm4.7"],
    //     "OPENAI_API_KEY",
    //     "OPENAI_BASE_URL"
    // ),
    ModelProviderPreset(
        "openai",
        "openai",
        "OpenAI Compatible",
        "models.providers.openai.apiKey",
        "models.providers.openai.baseUrl",
        "https://api.openai.com/v1",
        ["gpt-5", "gpt-5-mini", "gpt-4.1"]
    ),
    ModelProviderPreset(
        "anthropic",
        "anthropic",
        "Anthropic Compatible",
        "models.providers.anthropic.apiKey",
        "models.providers.anthropic.baseUrl",
        "https://api.anthropic.com/v1",
        ["claude-sonnet-4-5", "claude-3-7-sonnet-latest"]
    ),
    ModelProviderPreset(
        "deepseek",
        "deepseek",
        "Deepseek Compatible",
        "models.providers.deepseek.apiKey",
        "models.providers.deepseek.baseUrl",
        "https://api.deepseek.com/v1",
        ["deepseek-chat"]
    ),
    ModelProviderPreset(
        "maas",
        "maas",
        "ModelArts MaaS (Qwen2.5)",
        "models.providers.maas.apiKey",
        "models.providers.maas.baseUrl",
        "https://api.modelarts-maas.com/v1",
        ["qwen2.5-vl-72b"]
    )
]
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

private func getDefaultModelId(preset: ModelProviderPreset, currentModel: String): String {
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

