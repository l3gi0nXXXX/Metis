package metis.core.memory

import metis.core.config.MetisConfigManager

import std.fs.{File, exists, remove}
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonObject, JsonString}

private func memoryEmbeddingRuntimeReadConfigText(): Option<String> {
    let path = MetisConfigManager.configPath()
    if (!exists(path)) {
        return None<String>
    }
    Some(String.fromUtf8(File.readFrom(path)))
}

private func memoryEmbeddingRuntimeRestoreConfigText(previous: Option<String>): Unit {
    let path = MetisConfigManager.configPath()
    match (previous) {
        case Some(text) => File.writeTo(path, text.toArray())
        case None =>
            if (exists(path)) {
                remove(path)
            }
    }
    MetisConfigManager.invalidate()
    MetisConfigManager.initializeIfMissing()
}

private func memoryEmbeddingRuntimeString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

@Test
public class MemoryEmbeddingProviderRuntimeTest {
    @TestCase
    public func createRuntimeReturnsProviderAndRuntimeSummary(): Unit {
        clearMemoryEmbeddingProviders()
        let result = createMemoryEmbeddingProviderRuntime(
            "gemini",
            model: "gemini-embedding-001",
            outputDimensionality: 3072
        )
        let provider = result.provider.getOrThrow()
        let runtime = result.runtime.getOrThrow()
        @Expect(provider.id, "gemini")
        @Expect(provider.model, "gemini-embedding-001")
        @Expect(provider.transport, "remote")
        @Expect(provider.outputDimensionality, 3072)
        @Expect(runtime.id, "gemini")
        @Expect(runtime.batchEmbedSupported, true)
        let json = result.toJsonObject()
        let providerJson = json.get("provider").getOrThrow().asObject()
        let runtimeJson = json.get("runtime").getOrThrow().asObject()
        @Expect(memoryEmbeddingRuntimeString(providerJson, "id"), "gemini")
        @Expect(memoryEmbeddingRuntimeString(providerJson, "model"), "gemini-embedding-001")
        @Expect(memoryEmbeddingRuntimeString(runtimeJson, "id"), "gemini")
    }

    @TestCase
    public func createRuntimeAutoUsesConfiguredAgentProviderSelection(): Unit {
        let previousConfig = memoryEmbeddingRuntimeReadConfigText()
        try {
            clearMemoryEmbeddingProviders()
            let root = JsonObject()
            let agents = JsonObject()
            let defaults = JsonObject()
            let memorySearch = JsonObject()
            memorySearch.put("provider", JsonString("auto"))
            memorySearch.put("model", JsonString("embeddinggemma-300m-qat-Q8_0.gguf"))
            defaults.put("memorySearch", memorySearch)
            agents.put("defaults", defaults)
            root.put("agents", agents)
            MetisConfigManager.writeRoot(root)

            let result = createMemoryEmbeddingProviderRuntime("", agentId: "general")
            let provider = result.provider.getOrThrow()
            @Expect(provider.id, "local")
            @Expect(provider.model, "embeddinggemma-300m-qat-Q8_0.gguf")
            @Expect(provider.transport, "local")
        } finally {
            memoryEmbeddingRuntimeRestoreConfigText(previousConfig)
        }
    }

    @TestCase
    public func createRuntimeUnavailableAdapterReturnsErrorContract(): Unit {
        clearMemoryEmbeddingProviders()
        let result = createMemoryEmbeddingProviderRuntime("missing-provider")
        @Expect(result.provider.isNone(), true)
        @Expect(result.runtime.isNone(), true)
        @Expect(result.error, "memory embedding provider adapter unavailable")
        @Expect(result.continueAutoSelection, false)
    }

    @TestCase
    public func runtimeFallsBackToBuiltinCapabilityProvidersWhenRegistryIsCold(): Unit {
        clearMemoryEmbeddingProviders()
        @Expect(listRegisteredMemoryEmbeddingProviderAdapters().size, 0)
        let adapter = getMemoryEmbeddingProviderAdapter("ollama").getOrThrow()
        @Expect(adapter.id, "ollama")
        let created = createMemoryEmbeddingProviderRuntime("ollama")
        @Expect(created.provider.getOrThrow().id, "ollama")
    }

    @TestCase
    public func runtimePrefersRegisteredAdaptersOverBuiltinFallback(): Unit {
        clearMemoryEmbeddingProviders()
        registerMemoryEmbeddingProvider(
            MemoryEmbeddingProviderAdapter(
                "custom-embed",
                defaultModel: "custom-model",
                transport: "remote"
            ),
            ownerPluginId: "memory-core"
        )
        @Expect(getMemoryEmbeddingProviderAdapter("gemini").isNone(), true)
        let adapter = getMemoryEmbeddingProviderAdapter("custom-embed").getOrThrow()
        @Expect(adapter.id, "custom-embed")
        let created = createMemoryEmbeddingProviderRuntime("custom-embed")
        @Expect(created.provider.getOrThrow().id, "custom-embed")
    }
}
