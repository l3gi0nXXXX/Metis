package metis.program_support

import metis.core.config.{CliConfig, MetisConfigManager, cliFindModelAuthChoicesForProvider, cliSetupVisibleModelProviders}

import std.collection.{ArrayList, filter, map, collectArray}
import std.convert.Parsable
import stdx.encoding.json.{JsonArray, JsonObject, JsonValue}

public struct CliModelProviderPreset {
    CliModelProviderPreset(
        public let modelProvider: String,
        public let configProvider: String,
        public let name: String,
        public let apiKeyConfigPath: String,
        public let baseURLConfigPath: String,
        public let defaultBaseURL: String,
        public let suggestedModels: Array<String>
    ) { }
}

public func programSupportModelProviderPresets(): Array<CliModelProviderPreset> {
    [
    CliModelProviderPreset(
        "ark",
        "volcengine",
        "Volcano ARK Coding Plan",
        "models.providers.volcengine.apiKey",
        "models.providers.volcengine.baseUrl",
        "https://ark.cn-beijing.volces.com/api/coding/v3",
        ["ark-code-latest", "kimi-k2-250905"]
    ),
    CliModelProviderPreset(
        "moonshot",
        "moonshot",
        "Kimi Code",
        "models.providers.moonshot.apiKey",
        "models.providers.moonshot.baseUrl",
        "https://api.kimi.com/coding/v1",
        ["kimi-for-coding", "kimi-k2-0711-preview"]
    ),
    CliModelProviderPreset(
        "zhipuai",
        "zai",
        "GLM Coding Plan",
        "models.providers.zai.apiKey",
        "models.providers.zai.baseUrl",
        "https://open.bigmodel.cn/api/coding/paas/v4",
        ["glm-4.7", "glm-4.5"]
    ),
    CliModelProviderPreset(
        "openai",
        "openai",
        "OpenAI Compatible",
        "models.providers.openai.apiKey",
        "models.providers.openai.baseUrl",
        "https://api.openai.com/v1",
        ["gpt-5", "gpt-5-mini", "gpt-4.1"]
    ),
    CliModelProviderPreset(
        "anthropic",
        "anthropic",
        "Anthropic Compatible",
        "models.providers.anthropic.apiKey",
        "models.providers.anthropic.baseUrl",
        "https://api.anthropic.com/v1",
        ["claude-sonnet-4-5", "claude-3-7-sonnet-latest"]
    ),
    CliModelProviderPreset(
        "deepseek",
        "deepseek",
        "Deepseek Compatible",
        "models.providers.deepseek.apiKey",
        "models.providers.deepseek.baseUrl",
        "https://api.deepseek.com/v1",
        ["deepseek-chat"]
    ),
    CliModelProviderPreset(
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

public func programSupportIsMetisCommandLine(raw: String): Bool {
    let t = raw.trimAscii().toAsciiLower()
    t == "/metis" || t.startsWith("/metis ")
}

public func programSupportIsGatewayPluginCommandLine(raw: String): Bool {
    let t = raw.trimAscii().toAsciiLower()
    t == "/plugin" || t.startsWith("/plugin ")
}

public func programSupportIsGatewaySessionsCommandLine(raw: String): Bool {
    let t = raw.trimAscii().toAsciiLower()
    t == "/sessions" || t.startsWith("/sessions ")
}

public func programSupportIsGatewaySubagentsCommandLine(raw: String): Bool {
    let t = raw.trimAscii().toAsciiLower()
    t == "/subagents" || t.startsWith("/subagents ")
}

public func programSupportIsGatewayChannelCommandLine(raw: String): Bool {
    let t = raw.trimAscii().toAsciiLower()
    t == "/channel" || t.startsWith("/channel ")
}

public func programSupportIsGatewayCronCommandLine(raw: String): Bool {
    let t = raw.trimAscii().toAsciiLower()
    t == "/cron" || t.startsWith("/cron ")
}

public func programSupportIsModelsCommandLine(raw: String): Bool {
    let t = raw.trimAscii().toAsciiLower()
    t == "/models" || t == "models" || t.startsWith("/models ") || t.startsWith("models ")
}

public func programSupportRenderModelsHelp(): String {
    "Usage: /models [status|help|set-image|image-fallbacks|<provider>|<page>]\n" +
    "  /models              Open the interactive provider/model configuration flow and may write metis.json.\n" +
    "  /models status       Print read-only CLI chat model status.\n" +
    "  /models set-image <provider:model>  Set the dedicated image-understanding model.\n" +
    "  /models image-fallbacks add|remove|clear <provider:model>  Manage image-understanding fallbacks.\n" +
    "  /models help         Show this help.\n" +
    "  /models <provider>   Show read-only model candidates for a provider.\n" +
    "  /models <page>       Show a provider page.\n" +
    "  metis models set <provider:model>  Switch the persisted CLI model outside chat.\n"
}

public func programSupportRenderModelsStatus(): String {
    let current = CliConfig.modelOrEmpty().trimAscii()
    let model = if (current.isEmpty()) { "not set in current runtime" } else { current }
    let imageCurrent = CliConfig.imageModelOrEmpty().trimAscii()
    let imageModel = if (imageCurrent.isEmpty()) { "not set" } else { MetisConfigManager.canonicalModelRef(imageCurrent) }
    let imageFallbacks = if (CliConfig.imageFallbackModels.isEmpty()) {
        "[]"
    } else {
        let rendered = ArrayList<String>()
        for (item in CliConfig.imageFallbackModels) {
            rendered.add(MetisConfigManager.canonicalModelRef(item))
        }
        String.join(rendered.toArray(), delimiter: ", ")
    }
    "Models status (CLI chat)\n" +
    "  Current model: ${model}\n" +
    "  Image primary: ${imageModel}\n" +
    "  Image fallbacks: ${imageFallbacks}\n" +
    "  Scope: image understanding is independent from the main chat model; this is not gateway runtime status.\n" +
    "  Configure: use `/models`, `/models set-image <provider:model>`, or `metis models set-image <provider:model>` outside chat.\n"
}

public func programSupportRenderModelsProviderIndex(page: Int64): String {
    let providers = cliSetupVisibleModelProviders()
    let pageSize: Int64 = 8
    let total = Int64(providers.size)
    let totalPages = if (total <= 0) { 1 } else { (total + pageSize - 1) / pageSize }
    var effectivePage = page
    if (effectivePage < 1) {
        effectivePage = 1
    }
    if (effectivePage > totalPages) {
        effectivePage = totalPages
    }

    let sb = StringBuilder()
    sb.append("CLI models providers\n")
    sb.append("Current: ${programSupportRenderModelsCurrentText()}\n")
    sb.append("Page: ${effectivePage}/${totalPages}\n")
    let start = (effectivePage - 1) * pageSize
    let end = if (start + pageSize > total) { total } else { start + pageSize }
    for (idx in start..end) {
        let provider = providers[idx]
        let count = programSupportModelsCandidatesForProvider(provider.providerId).size
        let currentMark = if (programSupportModelsProviderFromRef(CliConfig.modelOrEmpty()) == provider.providerId) { " current" } else { "" }
        sb.append("- ${provider.providerId} (${count}) default=${provider.defaultModelRef}${currentMark}\n")
    }
    sb.append("Use: /models <provider>\n")
    if (effectivePage < totalPages) {
        sb.append("More: /models ${effectivePage + 1}\n")
    }
    sb.append("Switch: metis models set <provider:model>\n")
    sb.toString()
}

public func programSupportRenderModelsProviderModels(provider: String, page: Int64): String {
    let normalizedProvider = provider.trimAscii().toAsciiLower()
    let models = programSupportModelsCandidatesForProvider(normalizedProvider)
    if (models.isEmpty()) {
        let sb = StringBuilder()
        sb.append("Unknown provider or no models: ${normalizedProvider}\n")
        sb.append("Available providers:\n")
        for (descriptor in cliSetupVisibleModelProviders()) {
            sb.append("- ${descriptor.providerId}\n")
        }
        sb.append("Use: /models <provider>\n")
        return sb.toString()
    }

    let pageSize: Int64 = 8
    let total = Int64(models.size)
    let totalPages = if (total <= 0) { 1 } else { (total + pageSize - 1) / pageSize }
    var effectivePage = page
    if (effectivePage < 1) {
        effectivePage = 1
    }
    if (effectivePage > totalPages) {
        effectivePage = totalPages
    }

    let sb = StringBuilder()
    sb.append("Models (${normalizedProvider}) - ${total} available\n")
    sb.append("Current: ${programSupportRenderModelsCurrentText()}\n")
    sb.append("Page: ${effectivePage}/${totalPages}\n")
    let start = (effectivePage - 1) * pageSize
    let end = if (start + pageSize > total) { total } else { start + pageSize }
    for (idx in start..end) {
        let model = models[idx]
        let ref = "${normalizedProvider}:${model}"
        let mark = if (ref == CliConfig.modelOrEmpty().trimAscii()) { " *current*" } else { "" }
        sb.append("- ${normalizedProvider}/${model}${mark}\n")
    }
    sb.append("Back: /models\n")
    sb.append("Switch: metis models set <provider:model>\n")
    sb.toString()
}

private func programSupportRenderModelsCurrentText(): String {
    let current = CliConfig.modelOrEmpty().trimAscii()
    if (current.isEmpty()) {
        return "not set in current runtime"
    }
    current
}

private func programSupportModelsCandidatesForProvider(provider: String): Array<String> {
    let normalizedProvider = provider.trimAscii().toAsciiLower()
    let out = ArrayList<String>()
    for (descriptor in cliSetupVisibleModelProviders()) {
        if (descriptor.providerId == normalizedProvider) {
            programSupportAddModelsCandidate(out, normalizedProvider, descriptor.defaultModelRef)
        }
    }
    for (choice in cliFindModelAuthChoicesForProvider(normalizedProvider)) {
        programSupportAddModelsCandidate(out, normalizedProvider, choice.defaultModelRef)
    }
    programSupportAddModelsCandidate(out, normalizedProvider, CliConfig.modelOrEmpty())
    out.toArray()
}

private func programSupportAddModelsCandidate(out: ArrayList<String>, provider: String, modelRef: String): Unit {
    let modelProvider = programSupportModelsProviderFromRef(modelRef)
    if (modelProvider != provider.trimAscii().toAsciiLower()) {
        return
    }
    let modelId = programSupportModelsModelIdFromRef(modelRef)
    if (!modelId.isEmpty() && !out.contains(modelId)) {
        out.add(modelId)
    }
}

private func programSupportModelsProviderFromRef(modelRef: String): String {
    let value = modelRef.trimAscii()
    if (let Some(index) <- value.indexOf(b':')) {
        return value[..index].trimAscii().toAsciiLower()
    }
    ""
}

private func programSupportModelsModelIdFromRef(modelRef: String): String {
    let value = modelRef.trimAscii()
    if (let Some(index) <- value.indexOf(b':')) {
        return value[index + 1..].trimAscii()
    }
    value
}

public func programSupportIsModelsPageToken(value: String): Bool {
    try {
        let _ = Int64.parse(value.trimAscii())
        return true
    } catch (_: Exception) {
        return false
    }
}

public func programSupportParseModelsPage(value: String): Int64 {
    try {
        let parsed = Int64.parse(value.trimAscii())
        if (parsed < 1) {
            return 1
        }
        return parsed
    } catch (_: Exception) {
        return 1
    }
}

private let PROGRAM_SUPPORT_CLI_SUBAGENT_NOTICE_EVENT_KIND = "session.subagent.notice"

private func programSupportNoticeJsonString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func programSupportSubagentNoticeEventPayload(event: JsonObject): Option<JsonObject> {
    match (event.get("payload")) {
        case Some(v) =>
            try { Some(v.asObject()) } catch (_e: Exception) { None<JsonObject> }
        case None => None<JsonObject>
    }
}

public func programSupportCliSubagentNoticeFromGatewayEvent(event: JsonObject): Option<String> {
    if (programSupportNoticeJsonString(event, "kind") != PROGRAM_SUPPORT_CLI_SUBAGENT_NOTICE_EVENT_KIND) {
        return None<String>
    }
    let payload = match (programSupportSubagentNoticeEventPayload(event)) {
        case Some(v) => v
        case None => return None<String>
    }
    let notice = programSupportNoticeJsonString(payload, "notice")
    if (!notice.trimAscii().isEmpty()) {
        return Some(notice)
    }
    let text = programSupportNoticeJsonString(payload, "text")
    if (!text.trimAscii().isEmpty()) {
        return Some(text)
    }
    None<String>
}

public func programSupportCliSubagentNoticeGatewayEventSessionKey(event: JsonObject): String {
    let payload = match (programSupportSubagentNoticeEventPayload(event)) {
        case Some(v) => v
        case None => return ""
    }
    programSupportNoticeJsonString(payload, "sessionKey").trimAscii()
}

public func programSupportCliSubagentNoticeEventMatchesSession(event: JsonObject, sessionKey: String): Bool {
    let eventSessionKey = programSupportCliSubagentNoticeGatewayEventSessionKey(event)
    let expected = sessionKey.trimAscii()
    eventSessionKey == expected || (expected == "main" && eventSessionKey == "agent:general:main")
}

public func programSupportCliSubagentNoticesFromGatewayStreamResult(result: JsonValue, sessionKey: String): Array<String> {
    let notices = ArrayList<String>()
    try {
        let root = result.asObject()
        let pull = match (root.get("pull")) {
            case Some(v) => try { v.asObject() } catch (_inner: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let events = match (pull.get("events")) {
            case Some(v) => try { v.asArray() } catch (_inner: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        var i: Int64 = 0
        while (i < Int64(events.size())) {
            try {
                let event = events[i].asObject()
                if (programSupportCliSubagentNoticeEventMatchesSession(event, sessionKey)) {
                    match (programSupportCliSubagentNoticeFromGatewayEvent(event)) {
                        case Some(notice) => notices.add(notice)
                        case None => ()
                    }
                }
            } catch (_inner: Exception) {
                ()
            }
            i += 1
        }
    } catch (_e: Exception) {
        ()
    }
    notices.toArray()
}
