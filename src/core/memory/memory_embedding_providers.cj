package metis.core.memory

import std.collection.ArrayList

public class MemoryEmbeddingProviderAdapter {
    public let id: String
    public let defaultModel: String
    public let transport: String
    public let autoSelectPriority: Int64
    public let allowExplicitWhenConfiguredAuto: Bool
    public let supportsMultimodalEmbeddings: Bool
    public let defaultMaxInputTokens: Int64

    public init(
        id: String,
        defaultModel!: String = "",
        transport!: String = "remote",
        autoSelectPriority!: Int64 = 0,
        allowExplicitWhenConfiguredAuto!: Bool = false,
        supportsMultimodalEmbeddings!: Bool = false,
        defaultMaxInputTokens!: Int64 = 0
    ) {
        this.id = id.trimAscii()
        this.defaultModel = defaultModel.trimAscii()
        this.transport = transport.trimAscii()
        this.autoSelectPriority = autoSelectPriority
        this.allowExplicitWhenConfiguredAuto = allowExplicitWhenConfiguredAuto
        this.supportsMultimodalEmbeddings = supportsMultimodalEmbeddings
        this.defaultMaxInputTokens = defaultMaxInputTokens
    }
}

public class RegisteredMemoryEmbeddingProvider {
    public let adapter: MemoryEmbeddingProviderAdapter
    public let ownerPluginId: String

    public init(adapter: MemoryEmbeddingProviderAdapter, ownerPluginId!: String = "") {
        this.adapter = adapter
        this.ownerPluginId = ownerPluginId.trimAscii()
    }
}

private let memoryEmbeddingProviders = ArrayList<RegisteredMemoryEmbeddingProvider>()

private func memoryEmbeddingBuiltinProviders(): Array<RegisteredMemoryEmbeddingProvider> {
    [
        RegisteredMemoryEmbeddingProvider(
            MemoryEmbeddingProviderAdapter(
                "openai",
                defaultModel: "text-embedding-3-large",
                transport: "remote",
                autoSelectPriority: 100
            ),
            ownerPluginId: "memory-core"
        ),
        RegisteredMemoryEmbeddingProvider(
            MemoryEmbeddingProviderAdapter(
                "gemini",
                defaultModel: "gemini-embedding-001",
                transport: "remote",
                autoSelectPriority: 90,
                supportsMultimodalEmbeddings: true
            ),
            ownerPluginId: "memory-core"
        ),
        RegisteredMemoryEmbeddingProvider(
            MemoryEmbeddingProviderAdapter(
                "voyage",
                defaultModel: "voyage-3-large",
                transport: "remote",
                autoSelectPriority: 80
            ),
            ownerPluginId: "memory-core"
        ),
        RegisteredMemoryEmbeddingProvider(
            MemoryEmbeddingProviderAdapter(
                "mistral",
                defaultModel: "mistral-embed",
                transport: "remote",
                autoSelectPriority: 70
            ),
            ownerPluginId: "memory-core"
        ),
        RegisteredMemoryEmbeddingProvider(
            MemoryEmbeddingProviderAdapter(
                "bedrock",
                defaultModel: "amazon.titan-embed-text-v2:0",
                transport: "remote",
                autoSelectPriority: 60
            ),
            ownerPluginId: "memory-core"
        ),
        RegisteredMemoryEmbeddingProvider(
            MemoryEmbeddingProviderAdapter(
                "ollama",
                defaultModel: "nomic-embed-text",
                transport: "remote",
                autoSelectPriority: 50
            ),
            ownerPluginId: "memory-core"
        ),
        RegisteredMemoryEmbeddingProvider(
            MemoryEmbeddingProviderAdapter(
                "local",
                defaultModel: "embeddinggemma-300m-qat-Q8_0.gguf",
                transport: "local",
                autoSelectPriority: 110
            ),
            ownerPluginId: "memory-core"
        )
    ]
}

private func memoryEmbeddingCapabilityProviders(): Array<RegisteredMemoryEmbeddingProvider> {
    memoryEmbeddingBuiltinProviders()
}

public func registerMemoryEmbeddingProvider(
    adapter: MemoryEmbeddingProviderAdapter,
    ownerPluginId!: String = ""
): Unit {
    let normalized = adapter.id.trimAscii()
    for (i in 0..memoryEmbeddingProviders.size) {
        if (memoryEmbeddingProviders[i].adapter.id == normalized) {
            memoryEmbeddingProviders[i] = RegisteredMemoryEmbeddingProvider(adapter, ownerPluginId: ownerPluginId)
            return
        }
    }
    memoryEmbeddingProviders.add(RegisteredMemoryEmbeddingProvider(adapter, ownerPluginId: ownerPluginId))
}

public func getRegisteredMemoryEmbeddingProvider(id: String): Option<RegisteredMemoryEmbeddingProvider> {
    let normalized = id.trimAscii()
    for (entry in memoryEmbeddingProviders) {
        if (entry.adapter.id == normalized) {
            return Some(entry)
        }
    }
    None
}

public func getMemoryEmbeddingCapabilityProvider(id: String): Option<RegisteredMemoryEmbeddingProvider> {
    let normalized = id.trimAscii()
    for (entry in memoryEmbeddingCapabilityProviders()) {
        if (entry.adapter.id == normalized) {
            return Some(entry)
        }
    }
    None
}

public func getMemoryEmbeddingProvider(id: String): Option<MemoryEmbeddingProviderAdapter> {
    match (getRegisteredMemoryEmbeddingProvider(id)) {
        case Some(entry) => Some(entry.adapter)
        case None =>
            if (!memoryEmbeddingProviders.isEmpty()) {
                return None<MemoryEmbeddingProviderAdapter>
            }
            match (getMemoryEmbeddingCapabilityProvider(id)) {
                case Some(entry) => Some(entry.adapter)
                case None => None<MemoryEmbeddingProviderAdapter>
            }
    }
}

public func listRegisteredMemoryEmbeddingProviders(): Array<RegisteredMemoryEmbeddingProvider> {
    memoryEmbeddingProviders.toArray()
}

public func listMemoryEmbeddingProviders(): Array<MemoryEmbeddingProviderAdapter> {
    let out = ArrayList<MemoryEmbeddingProviderAdapter>()
    let source = if (!memoryEmbeddingProviders.isEmpty()) {
        memoryEmbeddingProviders.toArray()
    } else {
        memoryEmbeddingCapabilityProviders()
    }
    for (entry in source) {
        out.add(entry.adapter)
    }
    out.toArray()
}

public func restoreRegisteredMemoryEmbeddingProviders(entries: Array<RegisteredMemoryEmbeddingProvider>): Unit {
    memoryEmbeddingProviders.clear()
    for (entry in entries) {
        memoryEmbeddingProviders.add(entry)
    }
}

public func clearMemoryEmbeddingProviders(): Unit {
    memoryEmbeddingProviders.clear()
}
