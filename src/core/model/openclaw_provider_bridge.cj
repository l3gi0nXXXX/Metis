package metis.core.model

import metis.core.config.{
    cliCanonicalModelProviderId,
    cliProviderApiKeyConfigPath,
    cliProviderApiKeyEnvAliases,
    cliProviderBaseUrlConfigPath,
    cliProviderBaseUrlEnvAliases,
    cliRuntimeModelProviderId
}

import std.collection.{ArrayList, HashMap}

public class OpenClawProviderRegistration {
    public let id: String
    public let authKind: String
    public let configKeys: Array<String>
    public let models: Array<String>
    public let supportsStreaming: Bool
    public let supportsToolCalls: Bool
    public let supportsModelList: Bool

    public init(
        id: String,
        authKind!: String = "",
        configKeys!: Array<String> = [],
        models!: Array<String> = [],
        supportsStreaming!: Bool = false,
        supportsToolCalls!: Bool = false,
        supportsModelList!: Bool = false
    ) {
        this.id = id.trimAscii()
        this.authKind = authKind.trimAscii().toAsciiLower()
        this.configKeys = configKeys
        this.models = models
        this.supportsStreaming = supportsStreaming
        this.supportsToolCalls = supportsToolCalls
        this.supportsModelList = supportsModelList
    }
}

private func openClawProviderAppendUnique(items: ArrayList<String>, value: String): Unit {
    let trimmed = value.trimAscii()
    if (!trimmed.isEmpty() && !items.contains(trimmed)) {
        items.add(trimmed)
    }
}

private func openClawProviderNormalizeModelRef(providerId: String, model: String): String {
    let normalized = model.trimAscii()
    if (normalized.isEmpty()) {
        return ""
    }
    if (normalized.contains(":")) {
        return normalized
    }
    "${providerId.trimAscii().toAsciiLower()}:${normalized}"
}

private func openClawProviderNormalizeModels(providerId: String, models: Array<String>): Array<String> {
    let out = ArrayList<String>()
    for (model in models) {
        openClawProviderAppendUnique(out, openClawProviderNormalizeModelRef(providerId, model))
    }
    out.toArray()
}

private func openClawProviderConfigEnvAliases(providerId: String, configKeys: Array<String>, apiKey: Bool): Array<String> {
    let out = ArrayList<String>()
    for (key in configKeys) {
        let normalized = key.trimAscii()
        let lower = normalized.toAsciiLower()
        if (apiKey && (lower.contains("api_key") || lower.contains("apikey") || lower.contains("token"))) {
            openClawProviderAppendUnique(out, normalized)
        }
        if (!apiKey && lower.contains("base_url")) {
            openClawProviderAppendUnique(out, normalized)
        }
    }
    let catalog = if (apiKey) {
        cliProviderApiKeyEnvAliases(providerId)
    } else {
        cliProviderBaseUrlEnvAliases(providerId)
    }
    for (alias in catalog) {
        openClawProviderAppendUnique(out, alias)
    }
    out.toArray()
}

public class OpenClawProviderMetisBinding {
    public let contract: String = "metis.model-provider-registry.v1"
    public let pluginProviderId: String
    public let providerId: String
    public let runtimeProviderId: String
    public let authKind: String
    public let apiKeyConfigPath: String
    public let baseUrlConfigPath: String
    public let apiKeyEnvAliases: Array<String>
    public let baseUrlEnvAliases: Array<String>
    public let configKeys: Array<String>
    public let modelRefs: Array<String>
    public let supportsStreaming: Bool
    public let supportsToolCalls: Bool
    public let supportsModelList: Bool

    public init(registration: OpenClawProviderRegistration) {
        let canonical = cliCanonicalModelProviderId(registration.id)
        this.pluginProviderId = registration.id
        this.providerId = canonical
        this.runtimeProviderId = cliRuntimeModelProviderId(canonical)
        this.authKind = registration.authKind
        this.apiKeyConfigPath = cliProviderApiKeyConfigPath(canonical)
        this.baseUrlConfigPath = cliProviderBaseUrlConfigPath(canonical)
        this.apiKeyEnvAliases = openClawProviderConfigEnvAliases(canonical, registration.configKeys, true)
        this.baseUrlEnvAliases = openClawProviderConfigEnvAliases(canonical, registration.configKeys, false)
        this.configKeys = registration.configKeys
        this.modelRefs = openClawProviderNormalizeModels(canonical, registration.models)
        this.supportsStreaming = registration.supportsStreaming
        this.supportsToolCalls = registration.supportsToolCalls
        this.supportsModelList = registration.supportsModelList
    }

    public func toSafeSummary(): String {
        "contract=${this.contract};provider=${this.providerId};runtime=${this.runtimeProviderId};models=${String.join(this.modelRefs, delimiter: ",")};apiKeyPath=${this.apiKeyConfigPath};baseUrlPath=${this.baseUrlConfigPath}"
    }
}

public class OpenClawProviderProjection {
    public let id: String
    public let authKind: String
    public let configKeys: Array<String>
    public let models: Array<String>
    public let supportsStreaming: Bool
    public let supportsToolCalls: Bool
    public let supportsModelList: Bool

    public init(registration: OpenClawProviderRegistration) {
        this.id = registration.id
        this.authKind = registration.authKind
        this.configKeys = registration.configKeys
        this.models = registration.models
        this.supportsStreaming = registration.supportsStreaming
        this.supportsToolCalls = registration.supportsToolCalls
        this.supportsModelList = registration.supportsModelList
    }

    public func toSafeSummary(): String {
        "provider=${this.id};auth=${this.authKind};models=${String.join(this.models, delimiter: ",")};config=${String.join(this.configKeys, delimiter: ",")}"
    }
}

public class OpenClawProviderStreamChunk {
    public let kind: String
    public let content: String
    public let done: Bool

    public init(kind: String, content: String, done: Bool) {
        this.kind = kind
        this.content = content
        this.done = done
    }
}

public class OpenClawProviderToolCall {
    public let name: String
    public let argumentsJson: String

    public init(name: String, argumentsJson: String) {
        this.name = name.trimAscii()
        this.argumentsJson = argumentsJson
    }
}

public class OpenClawProviderBridgeCall {
    public let ok: Bool
    public let status: String
    public let method: String
    public let providerId: String
    public let runtimeProviderId: String
    public let modelRef: String
    public let prompt: String
    public let authConfigPath: String
    public let name: String
    public let argumentsJson: String
    public let error: String

    public init(
        ok: Bool,
        status: String,
        method: String,
        providerId: String,
        runtimeProviderId: String,
        modelRef: String,
        prompt!: String = "",
        authConfigPath!: String = "",
        name!: String = "",
        argumentsJson!: String = "",
        error!: String = ""
    ) {
        this.ok = ok
        this.status = status
        this.method = method
        this.providerId = providerId
        this.runtimeProviderId = runtimeProviderId
        this.modelRef = modelRef
        this.prompt = prompt
        this.authConfigPath = authConfigPath
        this.name = name
        this.argumentsJson = argumentsJson
        this.error = error
    }
}

public class OpenClawProviderBridgeRegistry {
    private let bindings = HashMap<String, OpenClawProviderMetisBinding>()
    private let providerOrder = ArrayList<String>()

    public init() {}

    public func registerProvider(registration: OpenClawProviderRegistration): OpenClawProviderMetisBinding {
        let binding = OpenClawProviderMetisBinding(registration)
        if (!this.providerOrder.contains(binding.providerId)) {
            this.providerOrder.add(binding.providerId)
        }
        this.bindings[binding.providerId] = binding
        if (binding.pluginProviderId != binding.providerId) {
            this.bindings[binding.pluginProviderId] = binding
        }
        binding
    }

    public func get(providerId: String): Option<OpenClawProviderMetisBinding> {
        this.bindings.get(cliCanonicalModelProviderId(providerId))
    }

    public func listProviderIds(): Array<String> {
        this.providerOrder.toArray()
    }

    public func listModels(providerId: String): Array<String> {
        match (this.get(providerId)) {
            case Some(binding) => if (binding.supportsModelList) { binding.modelRefs } else { [] }
            case None => []
        }
    }

    public func stream(providerId: String, model: String, prompt: String): OpenClawProviderBridgeCall {
        match (this.get(providerId)) {
            case Some(binding) =>
                if (!binding.supportsStreaming) {
                    return OpenClawProviderBridgeCall(
                        false,
                        "unsupported",
                        "openclaw.provider.stream",
                        binding.providerId,
                        binding.runtimeProviderId,
                        openClawProviderNormalizeModelRef(binding.providerId, model),
                        error: "provider does not advertise streaming"
                    )
                }
                OpenClawProviderBridgeCall(
                    true,
                    "ready",
                    "openclaw.provider.stream",
                    binding.providerId,
                    binding.runtimeProviderId,
                    openClawProviderNormalizeModelRef(binding.providerId, model),
                    prompt: prompt,
                    authConfigPath: binding.apiKeyConfigPath
                )
            case None =>
                OpenClawProviderBridgeCall(false, "not_found", "openclaw.provider.stream", "", "", "", error: "provider not registered")
        }
    }

    public func toolCall(providerId: String, name: String, argumentsJson: String): OpenClawProviderBridgeCall {
        match (this.get(providerId)) {
            case Some(binding) =>
                if (!binding.supportsToolCalls) {
                    return OpenClawProviderBridgeCall(
                        false,
                        "unsupported",
                        "openclaw.provider.toolCall",
                        binding.providerId,
                        binding.runtimeProviderId,
                        "",
                        error: "provider does not advertise tool calls"
                    )
                }
                OpenClawProviderBridgeCall(
                    true,
                    "ready",
                    "openclaw.provider.toolCall",
                    binding.providerId,
                    binding.runtimeProviderId,
                    "",
                    authConfigPath: binding.apiKeyConfigPath,
                    name: name.trimAscii(),
                    argumentsJson: argumentsJson
                )
            case None =>
                OpenClawProviderBridgeCall(false, "not_found", "openclaw.provider.toolCall", "", "", "", error: "provider not registered")
        }
    }
}

public class OpenClawProviderBridge {
    public static func project(registration: OpenClawProviderRegistration): OpenClawProviderProjection {
        OpenClawProviderProjection(registration)
    }

    public static func registerProvider(registration: OpenClawProviderRegistration): OpenClawProviderMetisBinding {
        OpenClawProviderMetisBinding(registration)
    }

    public static func fakeModelList(projection: OpenClawProviderProjection): Array<String> {
        if (!projection.supportsModelList) {
            return []
        }
        projection.models
    }

    public static func fakeStream(model: String, prompt: String): Array<OpenClawProviderStreamChunk> {
        [
            OpenClawProviderStreamChunk("partial-token", "[${model.trimAscii()}] ${prompt}", false),
            OpenClawProviderStreamChunk("done", "", true)
        ]
    }

    public static func fakeToolCall(name: String, argumentsJson: String): OpenClawProviderToolCall {
        OpenClawProviderToolCall(name, argumentsJson)
    }
}
