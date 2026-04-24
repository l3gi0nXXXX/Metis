package metis.core.memory

import metis.core.config.MetisConfigManager
import magic.jsonable.*
import std.collection.ArrayList
import stdx.encoding.json.{JsonObject, JsonString}

public class MemoryEmbeddingProviderRuntimeHost {
    public let id: String
    public let cacheKeyData: JsonObject
    public let batchEmbedSupported: Bool

    public init(
        id: String,
        cacheKeyData!: JsonObject = JsonObject(),
        batchEmbedSupported!: Bool = false
    ) {
        this.id = id.trimAscii()
        this.cacheKeyData = cacheKeyData
        this.batchEmbedSupported = batchEmbedSupported
    }

    public func toJsonObject(): JsonObject {
        let obj = JsonObject()
        obj.put("id", JsonString(id))
        obj.put("batchEmbedSupported", batchEmbedSupported.toJsonValue())
        if (cacheKeyData.toJsonString() != "{}") {
            obj.put("cacheKeyData", cacheKeyData)
        }
        obj
    }
}

public class MemoryEmbeddingProviderInstance {
    public let id: String
    public let model: String
    public let transport: String
    public let outputDimensionality: Int64
    public let maxInputTokens: Int64

    public init(
        id: String,
        model: String,
        transport: String,
        outputDimensionality!: Int64 = 0,
        maxInputTokens!: Int64 = 0
    ) {
        this.id = id.trimAscii()
        this.model = model.trimAscii()
        this.transport = transport.trimAscii()
        this.outputDimensionality = outputDimensionality
        this.maxInputTokens = maxInputTokens
    }

    public func toJsonObject(): JsonObject {
        let obj = JsonObject()
        obj.put("id", JsonString(id))
        obj.put("model", JsonString(model))
        obj.put("transport", JsonString(transport))
        if (outputDimensionality > 0) {
            obj.put("outputDimensionality", outputDimensionality.toJsonValue())
        }
        if (maxInputTokens > 0) {
            obj.put("maxInputTokens", maxInputTokens.toJsonValue())
        }
        obj
    }
}

public class MemoryEmbeddingProviderCreateResult {
    public let provider: Option<MemoryEmbeddingProviderInstance>
    public let runtime: Option<MemoryEmbeddingProviderRuntimeHost>
    public let error: String
    public let continueAutoSelection: Bool

    public init(
        provider!: Option<MemoryEmbeddingProviderInstance> = None,
        runtime!: Option<MemoryEmbeddingProviderRuntimeHost> = None,
        error!: String = "",
        continueAutoSelection!: Bool = false
    ) {
        this.provider = provider
        this.runtime = runtime
        this.error = error.trimAscii()
        this.continueAutoSelection = continueAutoSelection
    }

    public func toJsonObject(): JsonObject {
        let obj = JsonObject()
        obj.put("continueAutoSelection", continueAutoSelection.toJsonValue())
        if (!error.isEmpty()) {
            obj.put("error", JsonString(error))
        }
        match (provider) {
            case Some(value) => obj.put("provider", value.toJsonObject())
            case None => ()
        }
        match (runtime) {
            case Some(value) => obj.put("runtime", value.toJsonObject())
            case None => ()
        }
        obj
    }
}

private func autoSelectMemoryEmbeddingProviderAdapter(): Option<MemoryEmbeddingProviderAdapter> {
    let adapters = listMemoryEmbeddingProviderAdapters()
    if (adapters.isEmpty()) {
        return None<MemoryEmbeddingProviderAdapter>
    }
    var best = adapters[0]
    for (adapter in adapters) {
        if (adapter.autoSelectPriority > best.autoSelectPriority) {
            best = adapter
        }
    }
    Some(best)
}

public func listRegisteredMemoryEmbeddingProviderAdapters(): Array<MemoryEmbeddingProviderAdapter> {
    let out = ArrayList<MemoryEmbeddingProviderAdapter>()
    for (entry in listRegisteredMemoryEmbeddingProviders()) {
        out.add(entry.adapter)
    }
    out.toArray()
}

public func listMemoryEmbeddingProviderAdapters(): Array<MemoryEmbeddingProviderAdapter> {
    listMemoryEmbeddingProviders()
}

public func getMemoryEmbeddingProviderAdapter(id: String): Option<MemoryEmbeddingProviderAdapter> {
    getMemoryEmbeddingProvider(id.trimAscii())
}

public func resolveMemoryEmbeddingProviderAdapter(
    providerId: String,
    agentId!: String = ""
): Option<MemoryEmbeddingProviderAdapter> {
    let normalized = providerId.trimAscii()
    if (!normalized.isEmpty() && normalized != "auto") {
        return getMemoryEmbeddingProviderAdapter(normalized)
    }
    let resolvedAgentId = agentId.trimAscii()
    match (MetisConfigManager.readAgentMemorySearch(resolvedAgentId)) {
        case Some(cfg) =>
            match (cfg.get("provider")) {
                case Some(v) =>
                    try {
                        let id = v.asString().getValue().trimAscii()
                        if (!id.isEmpty() && id != "auto") {
                            return getMemoryEmbeddingProviderAdapter(id)
                        }
                        if (id == "auto") {
                            return autoSelectMemoryEmbeddingProviderAdapter()
                        }
                    } catch (_: Exception) {
                        ()
                    }
                case None => ()
            }
        case None => ()
    }
    if (normalized == "auto") {
        return autoSelectMemoryEmbeddingProviderAdapter()
    }
    autoSelectMemoryEmbeddingProviderAdapter()
}

public func createMemoryEmbeddingProviderRuntime(
    providerId: String,
    model!: String = "",
    outputDimensionality!: Int64 = 0,
    agentId!: String = ""
): MemoryEmbeddingProviderCreateResult {
    match (resolveMemoryEmbeddingProviderAdapter(providerId, agentId: agentId)) {
        case Some(adapter) =>
            let selectedModel = if (!model.trimAscii().isEmpty()) {
                model.trimAscii()
            } else {
                adapter.defaultModel.trimAscii()
            }
            let cacheKeyData = JsonObject()
            cacheKeyData.put("providerId", JsonString(adapter.id))
            cacheKeyData.put("model", JsonString(selectedModel))
            cacheKeyData.put("transport", JsonString(adapter.transport))
            let provider = MemoryEmbeddingProviderInstance(
                adapter.id,
                selectedModel,
                adapter.transport,
                outputDimensionality: outputDimensionality,
                maxInputTokens: adapter.defaultMaxInputTokens
            )
            let runtime = MemoryEmbeddingProviderRuntimeHost(
                adapter.id,
                cacheKeyData: cacheKeyData,
                batchEmbedSupported: true
            )
            MemoryEmbeddingProviderCreateResult(
                provider: Some(provider),
                runtime: Some(runtime)
            )
        case None =>
            MemoryEmbeddingProviderCreateResult(
                error: "memory embedding provider adapter unavailable",
                continueAutoSelection: providerId.trimAscii() == "auto"
            )
    }
}
