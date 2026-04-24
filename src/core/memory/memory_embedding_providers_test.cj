package metis.core.memory

import metis.core.config.MetisConfigManager

import std.fs.{File, exists, remove}
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonObject, JsonString}

private func memoryEmbeddingProvidersReadConfigText(): Option<String> {
    let path = MetisConfigManager.configPath()
    if (!exists(path)) {
        return None<String>
    }
    Some(String.fromUtf8(File.readFrom(path)))
}

private func memoryEmbeddingProvidersRestoreConfigText(previous: Option<String>): Unit {
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

@Test
public class MemoryEmbeddingProvidersTest {
    @TestCase
    public func listsBuiltinAdaptersInStableOrder(): Unit {
        clearMemoryEmbeddingProviders()
        @Expect(listRegisteredMemoryEmbeddingProviders().size, 0)
        let adapters = listMemoryEmbeddingProviders()
        @Expect(adapters.size, 7)
        @Expect(adapters[0].id, "openai")
        @Expect(adapters[1].id, "gemini")
        @Expect(adapters[2].id, "voyage")
        @Expect(adapters[3].id, "mistral")
        @Expect(adapters[4].id, "bedrock")
        @Expect(adapters[5].id, "ollama")
        @Expect(adapters[6].id, "local")
        @Expect(adapters[6].transport, "local")
    }

    @TestCase
    public func registerAndLookupProviderTracksOwnerPlugin(): Unit {
        clearMemoryEmbeddingProviders()
        registerMemoryEmbeddingProvider(
            MemoryEmbeddingProviderAdapter(
                "custom-embed",
                defaultModel: "custom-model",
                transport: "remote",
                supportsMultimodalEmbeddings: true
            ),
            ownerPluginId: "memory-core"
        )
        let registered = getRegisteredMemoryEmbeddingProvider("custom-embed").getOrThrow()
        @Expect(registered.adapter.id, "custom-embed")
        @Expect(registered.adapter.defaultModel, "custom-model")
        @Expect(registered.ownerPluginId, "memory-core")
        @Expect(registered.adapter.supportsMultimodalEmbeddings, true)
        @Expect(registered.adapter.defaultMaxInputTokens, 0)
        @Expect(getMemoryEmbeddingProvider("custom-embed").getOrThrow().id, "custom-embed")
        @Expect(listMemoryEmbeddingProviders().size, 1)
    }

    @TestCase
    public func builtinFallbackDoesNotPretendProvidersAreRegistered(): Unit {
        clearMemoryEmbeddingProviders()
        @Expect(getRegisteredMemoryEmbeddingProvider("gemini").isNone(), true)
        let builtin = getMemoryEmbeddingProvider("gemini").getOrThrow()
        @Expect(builtin.id, "gemini")
        let capability = getMemoryEmbeddingCapabilityProvider("gemini").getOrThrow()
        @Expect(capability.ownerPluginId, "memory-core")
    }

    @TestCase
    public func resolveRuntimeAdapterAutoSelectsHighestPriorityProvider(): Unit {
        clearMemoryEmbeddingProviders()
        let adapter = resolveMemoryEmbeddingProviderAdapter("auto").getOrThrow()
        @Expect(adapter.id, "local")
    }

    @TestCase
    public func resolveRuntimeAdapterUsesAgentMemorySearchAutoSelection(): Unit {
        let previousConfig = memoryEmbeddingProvidersReadConfigText()
        try {
            clearMemoryEmbeddingProviders()
            let root = JsonObject()
            let agents = JsonObject()
            let defaults = JsonObject()
            let memorySearch = JsonObject()
            memorySearch.put("provider", JsonString("auto"))
            defaults.put("memorySearch", memorySearch)
            agents.put("defaults", defaults)
            root.put("agents", agents)
            MetisConfigManager.writeRoot(root)

            let adapter = resolveMemoryEmbeddingProviderAdapter("", agentId: "general").getOrThrow()
            @Expect(adapter.id, "local")
        } finally {
            memoryEmbeddingProvidersRestoreConfigText(previousConfig)
        }
    }
}
