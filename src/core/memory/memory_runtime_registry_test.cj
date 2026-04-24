package metis.core.memory

import magic.jsonable.*

import metis.core.config.CliConfig
import metis.core.config.MetisConfigManager

import std.fs.{Directory, File, exists, remove}
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private func memoryRuntimeTestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func memoryRuntimeTestIssueContains(issues: JsonValue, expected: String): Bool {
    try {
        let arr = issues.asArray()
        for (i in 0..arr.size()) {
            let item = arr[i]
            try {
                if (item.asString().getValue().contains(expected)) {
                    return true
                }
            } catch (_: Exception) {
                ()
            }
        }
    } catch (_: Exception) {
        ()
    }
    false
}

private func memoryRuntimeTestReadConfigText(): Option<String> {
    let path = MetisConfigManager.configPath()
    if (!exists(path)) {
        return None<String>
    }
    Some(String.fromUtf8(File.readFrom(path)))
}

private func memoryRuntimeTestRestoreConfigText(previous: Option<String>): Unit {
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
public class MemoryRuntimeRegistryTest {
    @TestCase
    public func resolveBackendConfigCarriesResolvedMetadata(): Unit {
        let resolved = MemoryRuntimeRegistry.resolveBackendConfig(agentId: "general", purpose: "tool-search")
        @Expect(resolved.agentId, "general")
        @Expect(resolved.purpose, "tool-search")
        @Expect(resolved.configScope, "global")
        @Expect(resolved.citations, CliConfig.memoryCitations)
        @Expect(resolved.providerId.isEmpty(), false)
        @Expect(resolved.backend.isEmpty(), false)
        let cfg = resolved.toJsonObject()
        @Expect(cfg.get("backendConfig").isSome(), true)
        @Expect(cfg.get("selectionKeys").isSome(), true)
        @Expect(cfg.get("configTemplate").isSome(), true)
        @Expect(cfg.get("registrationMetadata").isSome(), true)
        @Expect(cfg.get("configValidation").isSome(), true)
        @Expect(cfg.get("configSchema").isSome(), true)
    }

    @TestCase
    public func activeMemoryPluginDefaultsToMemoryCoreSlot(): Unit {
        let summary = MemoryRuntimeRegistry.activeMemoryPluginSummary(
            agentId: "general",
            purpose: "tool-search"
        )
        @Expect(memoryRuntimeTestString(summary, "pluginId"), "memory-core")
        @Expect(memoryRuntimeTestString(summary, "slot"), "memory")
        @Expect(summary.get("ownsRuntime").getOrThrow().asBool().getValue(), true)
        @Expect(summary.get("registersPromptSection").getOrThrow().asBool().getValue(), true)
        @Expect(summary.get("registersFlushPlan").getOrThrow().asBool().getValue(), true)
        @Expect(summary.get("registersRuntimeAdapter").getOrThrow().asBool().getValue(), true)
        @Expect(memoryRuntimeTestString(summary, "runtimeBridge"), "registered-memory-runtime")
    }

    @TestCase
    public func activeMemoryPluginHonorsExplicitNoneSlot(): Unit {
        let previousConfig = memoryRuntimeTestReadConfigText()
        try {
            let root = JsonObject()
            let plugins = JsonObject()
            let slots = JsonObject()
            slots.put("memory", JsonString("none"))
            plugins.put("slots", slots)
            root.put("plugins", plugins)
            MetisConfigManager.writeRoot(root)

            let summary = MemoryRuntimeRegistry.activeMemoryPluginSummary(
                agentId: "general",
                purpose: "tool-search"
            )
            let resolved = MemoryRuntimeRegistry.resolveBackendConfig(
                agentId: "general",
                purpose: "tool-search"
            )
            let selection = MemoryRuntimeRegistry.backendSelectionSummary(
                agentId: "general",
                purpose: "tool-search"
            )
            let scoped = MemoryRuntimeRegistry.agentScopedResolveSummary(
                agentId: "general",
                purpose: "tool-search"
            )
            let activeSearch = MemoryRuntimeRegistry.activeSearchBackendSummary(
                agentId: "general",
                purpose: "tool-search"
            )
            let activeOrchestration = MemoryRuntimeRegistry.activeOrchestrationBackendSummary(
                agentId: "general",
                purpose: "tool-search"
            )
            let available = MemoryRuntimeRegistry.registeredMemoryPluginSummaries()
            @Expect(memoryRuntimeTestString(summary, "pluginId"), "none")
            @Expect(summary.get("ownsRuntime").getOrThrow().asBool().getValue(), false)
            @Expect(resolved.configScope, "plugins.slots.memory")
            @Expect(resolved.memoryPluginId, "none")
            @Expect(resolved.memoryPluginAvailable, false)
            @Expect(resolved.providerId, "")
            @Expect(resolved.backend, "")
            @Expect(memoryRuntimeTestString(selection, "selectionMode"), "memory-plugin-disabled")
            @Expect(memoryRuntimeTestString(scoped, "scopeSource"), "plugins.slots.memory")
            @Expect(activeSearch.get("active").getOrThrow().asBool().getValue(), false)
            @Expect(activeOrchestration.get("active").getOrThrow().asBool().getValue(), false)
            @Expect(memoryRuntimeTestString(activeOrchestration, "backendId"), "")
            @Expect(available.size() > 0, true)
        } finally {
            memoryRuntimeTestRestoreConfigText(previousConfig)
        }
    }

    @TestCase
    public func resolveBackendConfigPrefersAgentsDefaultMemorySearchProvider(): Unit {
        let previousConfig = memoryRuntimeTestReadConfigText()
        try {
            let root = JsonObject()
            let agents = JsonObject()
            let defaults = JsonObject()
            let memorySearch = JsonObject()
            memorySearch.put("provider", JsonString("qmd"))
            defaults.put("memorySearch", memorySearch)
            agents.put("defaults", defaults)
            root.put("agents", agents)
            let memory = JsonObject()
            memory.put("backend", JsonString("local"))
            root.put("memory", memory)
            MetisConfigManager.writeRoot(root)

            let resolved = MemoryRuntimeRegistry.resolveBackendConfig(agentId: "general", purpose: "tool-search")
            let selection = MemoryRuntimeRegistry.backendSelectionSummary(agentId: "general", purpose: "tool-search")
            let scoped = MemoryRuntimeRegistry.agentScopedResolveSummary(agentId: "general", purpose: "tool-search")
            @Expect(resolved.providerId, "qmd")
            @Expect(resolved.backend, "qmd")
            @Expect(resolved.configScope, "agents.defaults.memorySearch")
            @Expect(memoryRuntimeTestString(selection, "requestedBackend"), "qmd")
            @Expect(memoryRuntimeTestString(selection, "selectionMode"), "provider-id")
            @Expect(memoryRuntimeTestString(scoped, "scopeSource"), "agents.defaults.memorySearch")
        } finally {
            memoryRuntimeTestRestoreConfigText(previousConfig)
        }
    }

    @TestCase
    public func resolveBackendConfigPrefersAgentMemorySearchOverride(): Unit {
        let previousConfig = memoryRuntimeTestReadConfigText()
        try {
            let root = JsonObject()
            let agents = JsonObject()
            let defaults = JsonObject()
            let defaultMemorySearch = JsonObject()
            defaultMemorySearch.put("provider", JsonString("qmd"))
            defaults.put("memorySearch", defaultMemorySearch)
            agents.put("defaults", defaults)
            let list = JsonArray([])
            let entry = JsonObject()
            entry.put("id", JsonString("general"))
            let overrideMemorySearch = JsonObject()
            overrideMemorySearch.put("provider", JsonString("local"))
            entry.put("memorySearch", overrideMemorySearch)
            list.add(entry)
            agents.put("list", list)
            root.put("agents", agents)
            MetisConfigManager.writeRoot(root)

            let resolved = MemoryRuntimeRegistry.resolveBackendConfig(agentId: "general", purpose: "tool-search")
            let scoped = MemoryRuntimeRegistry.agentScopedResolveSummary(agentId: "general", purpose: "tool-search")
            @Expect(resolved.providerId, "local")
            @Expect(resolved.configScope, "agents.list[].memorySearch")
            @Expect(memoryRuntimeTestString(scoped, "scopeSource"), "agents.list[].memorySearch")
        } finally {
            memoryRuntimeTestRestoreConfigText(previousConfig)
        }
    }

    @TestCase
    public func memorySearchDisabledReturnsDisabledResolvedConfig(): Unit {
        let previousConfig = memoryRuntimeTestReadConfigText()
        try {
            let root = JsonObject()
            let agents = JsonObject()
            let defaults = JsonObject()
            let memorySearch = JsonObject()
            memorySearch.put("provider", JsonString("qmd"))
            memorySearch.put("enabled", false.toJsonValue())
            defaults.put("memorySearch", memorySearch)
            agents.put("defaults", defaults)
            root.put("agents", agents)
            MetisConfigManager.writeRoot(root)

            let resolved = MemoryRuntimeRegistry.resolveBackendConfig(agentId: "general", purpose: "tool-search")
            let selection = MemoryRuntimeRegistry.backendSelectionSummary(agentId: "general", purpose: "tool-search")
            let activeSearch = MemoryRuntimeRegistry.activeSearchBackendSummary(agentId: "general", purpose: "tool-search")
            let activeOrchestration = MemoryRuntimeRegistry.activeOrchestrationBackendSummary(agentId: "general", purpose: "tool-search")
            let manager = MemoryRuntimeRegistry.getActiveSearchManager(agentId: "general", purpose: "tool-search")
            @Expect(resolved.providerId, "")
            @Expect(resolved.backend, "")
            @Expect(resolved.searchEnabled, false)
            @Expect(resolved.configScope, "agents.defaults.memorySearch")
            @Expect(memoryRuntimeTestString(selection, "selectionMode"), "memory-search-disabled")
            @Expect(activeSearch.get("active").getOrThrow().asBool().getValue(), false)
            @Expect(activeOrchestration.get("active").getOrThrow().asBool().getValue(), false)
            @Expect(manager.manager.isNone(), true)
            @Expect(manager.error, "memory search disabled")
        } finally {
            memoryRuntimeTestRestoreConfigText(previousConfig)
        }
    }

    @TestCase
    public func resolvedBackendConfigCarriesMemorySearchStructureFields(): Unit {
        let previousConfig = memoryRuntimeTestReadConfigText()
        try {
            let root = JsonObject()
            let agents = JsonObject()
            let defaults = JsonObject()
            let memorySearch = JsonObject()
            memorySearch.put("provider", JsonString("qmd"))
            memorySearch.put("fallback", JsonString("local"))
            memorySearch.put("extraPaths", JsonArray([JsonString("/docs"), JsonString("/shared")]))
            let qmd = JsonObject()
            qmd.put("extraCollections", JsonArray([JsonString("team"), JsonString("ops")]))
            memorySearch.put("qmd", qmd)
            defaults.put("memorySearch", memorySearch)
            agents.put("defaults", defaults)
            root.put("agents", agents)
            MetisConfigManager.writeRoot(root)

            let resolved = MemoryRuntimeRegistry.resolveBackendConfig(agentId: "general", purpose: "tool-search")
            let json = resolved.toJsonObject()
            @Expect(resolved.fallbackProviderId, "local")
            @Expect(resolved.extraPaths.size, 2)
            @Expect(resolved.qmdExtraCollections.size, 2)
            @Expect(memoryRuntimeTestString(json, "fallbackProviderId"), "local")
            @Expect(json.get("extraPaths").getOrThrow().asArray().size(), 2)
            @Expect(json.get("qmdExtraCollections").getOrThrow().asArray().size(), 2)
            let registrationMetadata = json.get("registrationMetadata").getOrThrow().asObject()
            @Expect(memoryRuntimeTestString(registrationMetadata, "memorySearchFallback"), "local")
        } finally {
            memoryRuntimeTestRestoreConfigText(previousConfig)
        }
    }

    @TestCase
    public func previewAgentScopedResolveSummaryIncludesMergedMemorySearchFields(): Unit {
        let previousConfig = memoryRuntimeTestReadConfigText()
        try {
            let root = JsonObject()
            let agents = JsonObject()
            let defaults = JsonObject()
            let memorySearch = JsonObject()
            memorySearch.put("provider", JsonString("qmd"))
            memorySearch.put("fallback", JsonString("local"))
            memorySearch.put("extraPaths", JsonArray([JsonString("/docs")]))
            let qmd = JsonObject()
            qmd.put("extraCollections", JsonArray([JsonString("team")]))
            memorySearch.put("qmd", qmd)
            defaults.put("memorySearch", memorySearch)
            agents.put("defaults", defaults)
            let list = JsonArray([])
            let entry = JsonObject()
            entry.put("id", JsonString("general"))
            let overrideMemorySearch = JsonObject()
            overrideMemorySearch.put("fallback", JsonString("voyage"))
            overrideMemorySearch.put("extraPaths", JsonArray([JsonString("/project")]))
            let overrideQmd = JsonObject()
            overrideQmd.put("extraCollections", JsonArray([JsonString("project")]))
            overrideMemorySearch.put("qmd", overrideQmd)
            entry.put("memorySearch", overrideMemorySearch)
            list.add(entry)
            agents.put("list", list)
            root.put("agents", agents)
            MetisConfigManager.writeRoot(root)

            let preview = MemoryRuntimeRegistry.previewAgentScopedResolveSummary(
                "qmd",
                agentId: "general",
                purpose: "preview"
            )
            let resolved = preview.get("resolvedBackendConfig").getOrThrow().asObject()
            @Expect(memoryRuntimeTestString(resolved, "fallbackProviderId"), "voyage")
            @Expect(resolved.get("extraPaths").getOrThrow().asArray().size(), 2)
            @Expect(resolved.get("qmdExtraCollections").getOrThrow().asArray().size(), 2)
        } finally {
            memoryRuntimeTestRestoreConfigText(previousConfig)
        }
    }

    @TestCase
    public func resolvedBackendConfigCarriesMemorySearchModelAndRemoteConfig(): Unit {
        let previousConfig = memoryRuntimeTestReadConfigText()
        try {
            let root = JsonObject()
            let agents = JsonObject()
            let defaults = JsonObject()
            let memorySearch = JsonObject()
            memorySearch.put("provider", JsonString("qmd"))
            memorySearch.put("model", JsonString("text-embedding-3-small"))
            let remote = JsonObject()
            remote.put("baseUrl", JsonString("https://memory.example/v1"))
            remote.put("apiKey", JsonString("secret-token"))
            let headers = JsonObject()
            headers.put("x-memory", JsonString("enabled"))
            remote.put("headers", headers)
            memorySearch.put("remote", remote)
            defaults.put("memorySearch", memorySearch)
            agents.put("defaults", defaults)
            root.put("agents", agents)
            MetisConfigManager.writeRoot(root)

            let resolved = MemoryRuntimeRegistry.resolveBackendConfig(agentId: "general", purpose: "tool-search")
            let json = resolved.toJsonObject()
            @Expect(resolved.model, "text-embedding-3-small")
            @Expect(resolved.remoteBaseUrl, "https://memory.example/v1")
            @Expect(resolved.remoteApiKey, "secret-token")
            @Expect(memoryRuntimeTestString(json, "model"), "text-embedding-3-small")
            let remoteJson = json.get("remote").getOrThrow().asObject()
            @Expect(memoryRuntimeTestString(remoteJson, "baseUrl"), "https://memory.example/v1")
            @Expect(memoryRuntimeTestString(remoteJson, "apiKey"), "secret-token")
            @Expect(
                remoteJson.get("headers").getOrThrow().asObject().get("x-memory").getOrThrow().asString().getValue(),
                "enabled"
            )
            let registrationMetadata = json.get("registrationMetadata").getOrThrow().asObject()
            @Expect(memoryRuntimeTestString(registrationMetadata, "memorySearchModel"), "text-embedding-3-small")
            @Expect(registrationMetadata.get("memorySearchRemoteConfigured").getOrThrow().asBool().getValue(), true)
        } finally {
            memoryRuntimeTestRestoreConfigText(previousConfig)
        }
    }

    @TestCase
    public func resolvedBackendConfigCarriesMemorySearchLocalAndHybridConfig(): Unit {
        let previousConfig = memoryRuntimeTestReadConfigText()
        try {
            let root = JsonObject()
            let agents = JsonObject()
            let defaults = JsonObject()
            let memorySearch = JsonObject()
            memorySearch.put("provider", JsonString("local"))
            let local = JsonObject()
            local.put("modelPath", JsonString("/models/embedding.gguf"))
            local.put("modelCacheDir", JsonString("/cache/embeddings"))
            memorySearch.put("local", local)
            let hybrid = JsonObject()
            hybrid.put("enabled", true.toJsonValue())
            hybrid.put("vectorWeight", 0.6.toJsonValue())
            let mmr = JsonObject()
            mmr.put("enabled", true.toJsonValue())
            mmr.put("lambda", 0.8.toJsonValue())
            hybrid.put("mmr", mmr)
            let query = JsonObject()
            query.put("hybrid", hybrid)
            memorySearch.put("query", query)
            defaults.put("memorySearch", memorySearch)
            agents.put("defaults", defaults)
            root.put("agents", agents)
            MetisConfigManager.writeRoot(root)

            let resolved = MemoryRuntimeRegistry.resolveBackendConfig(agentId: "general", purpose: "tool-search")
            let json = resolved.toJsonObject()
            let localJson = json.get("local").getOrThrow().asObject()
            @Expect(memoryRuntimeTestString(localJson, "modelPath"), "/models/embedding.gguf")
            @Expect(memoryRuntimeTestString(localJson, "modelCacheDir"), "/cache/embeddings")
            let hybridJson = json.get("query").getOrThrow().asObject().get("hybrid").getOrThrow().asObject()
            @Expect(hybridJson.get("enabled").getOrThrow().asBool().getValue(), true)
            @Expect(hybridJson.get("vectorWeight").getOrThrow().asFloat().getValue(), 0.6)
            let mmrJson = hybridJson.get("mmr").getOrThrow().asObject()
            @Expect(mmrJson.get("enabled").getOrThrow().asBool().getValue(), true)
            @Expect(mmrJson.get("lambda").getOrThrow().asFloat().getValue(), 0.8)
        } finally {
            memoryRuntimeTestRestoreConfigText(previousConfig)
        }
    }

    @TestCase
    public func resolvedBackendConfigCarriesMemorySearchStoreAndSyncConfig(): Unit {
        let previousConfig = memoryRuntimeTestReadConfigText()
        try {
            let root = JsonObject()
            let agents = JsonObject()
            let defaults = JsonObject()
            let memorySearch = JsonObject()
            memorySearch.put("provider", JsonString("local"))
            let store = JsonObject()
            store.put("driver", JsonString("sqlite"))
            store.put("path", JsonString("/tmp/memory-{agentId}.sqlite"))
            let vector = JsonObject()
            vector.put("enabled", true.toJsonValue())
            vector.put("extensionPath", JsonString("/tmp/sqlite-vec.dylib"))
            store.put("vector", vector)
            memorySearch.put("store", store)
            let sync = JsonObject()
            sync.put("watch", true.toJsonValue())
            sync.put("watchDebounceMs", 2500.toJsonValue())
            let sessions = JsonObject()
            sessions.put("deltaBytes", 4096.toJsonValue())
            sessions.put("postCompactionForce", true.toJsonValue())
            sync.put("sessions", sessions)
            memorySearch.put("sync", sync)
            defaults.put("memorySearch", memorySearch)
            agents.put("defaults", defaults)
            root.put("agents", agents)
            MetisConfigManager.writeRoot(root)

            let resolved = MemoryRuntimeRegistry.resolveBackendConfig(agentId: "general", purpose: "tool-search")
            let json = resolved.toJsonObject()
            let storeJson = json.get("store").getOrThrow().asObject()
            @Expect(memoryRuntimeTestString(storeJson, "driver"), "sqlite")
            @Expect(memoryRuntimeTestString(storeJson, "path"), "/tmp/memory-{agentId}.sqlite")
            let vectorJson = storeJson.get("vector").getOrThrow().asObject()
            @Expect(vectorJson.get("enabled").getOrThrow().asBool().getValue(), true)
            @Expect(memoryRuntimeTestString(vectorJson, "extensionPath"), "/tmp/sqlite-vec.dylib")
            let syncJson = json.get("sync").getOrThrow().asObject()
            @Expect(syncJson.get("watch").getOrThrow().asBool().getValue(), true)
            @Expect(syncJson.get("watchDebounceMs").getOrThrow().asInt().getValue(), 2500)
            let sessionsJson = syncJson.get("sessions").getOrThrow().asObject()
            @Expect(sessionsJson.get("deltaBytes").getOrThrow().asInt().getValue(), 4096)
            @Expect(sessionsJson.get("postCompactionForce").getOrThrow().asBool().getValue(), true)
        } finally {
            memoryRuntimeTestRestoreConfigText(previousConfig)
        }
    }

    @TestCase
    public func resolvedBackendConfigCarriesMemorySearchOutputDimensionalityAndMultimodal(): Unit {
        let previousConfig = memoryRuntimeTestReadConfigText()
        try {
            let root = JsonObject()
            let agents = JsonObject()
            let defaults = JsonObject()
            let memorySearch = JsonObject()
            memorySearch.put("provider", JsonString("openai"))
            memorySearch.put("outputDimensionality", 3072.toJsonValue())
            let multimodal = JsonObject()
            multimodal.put("enabled", true.toJsonValue())
            multimodal.put("modalities", JsonArray([JsonString("image"), JsonString("audio")]))
            multimodal.put("maxFileBytes", 123456.toJsonValue())
            memorySearch.put("multimodal", multimodal)
            defaults.put("memorySearch", memorySearch)
            agents.put("defaults", defaults)
            root.put("agents", agents)
            MetisConfigManager.writeRoot(root)

            let resolved = MemoryRuntimeRegistry.resolveBackendConfig(agentId: "general", purpose: "tool-search")
            let json = resolved.toJsonObject()
            @Expect(resolved.outputDimensionality, 3072)
            @Expect(json.get("outputDimensionality").getOrThrow().asInt().getValue(), 3072)
            let multimodalJson = json.get("multimodal").getOrThrow().asObject()
            @Expect(multimodalJson.get("enabled").getOrThrow().asBool().getValue(), true)
            @Expect(multimodalJson.get("modalities").getOrThrow().asArray().size(), 2)
            @Expect(multimodalJson.get("maxFileBytes").getOrThrow().asInt().getValue(), 123456)
            let registrationMetadata = json.get("registrationMetadata").getOrThrow().asObject()
            @Expect(registrationMetadata.get("memorySearchOutputDimensionality").getOrThrow().asInt().getValue(), 3072)
        } finally {
            memoryRuntimeTestRestoreConfigText(previousConfig)
        }
    }

    /*
    @TestCase
    public func resolvedBackendConfigCarriesEmbeddingProviderSummary(): Unit {
        let previousConfig = memoryRuntimeTestReadConfigText()
        try {
            let root = JsonObject()
            let agents = JsonObject()
            let defaults = JsonObject()
            let memorySearch = JsonObject()
            memorySearch.put("provider", JsonString("gemini"))
            defaults.put("memorySearch", memorySearch)
            agents.put("defaults", defaults)
            root.put("agents", agents)
            MetisConfigManager.writeRoot(root)

            let resolved = MemoryRuntimeRegistry.resolveBackendConfig(agentId: "general", purpose: "tool-search")
            let json = resolved.toJsonObject()
            @Expect(resolved.embeddingProviderId, "gemini")
            @Expect(resolved.embeddingProviderTransport, "remote")
            @Expect(resolved.embeddingProviderDefaultModel, "gemini-embedding-001")
            @Expect(resolved.embeddingProviderOwnerPluginId, "memory-core")
            @Expect(resolved.embeddingProviderRegistered, false)
            @Expect(resolved.embeddingProviderSupportsMultimodal, true)
            @Expect(resolved.embeddingProviderAllowExplicitWhenConfiguredAuto, false)
            let adapterJson = json.get("embeddingProvider").getOrThrow().asObject()
            @Expect(memoryRuntimeTestString(adapterJson, "id"), "gemini")
            @Expect(memoryRuntimeTestString(adapterJson, "transport"), "remote")
            @Expect(memoryRuntimeTestString(adapterJson, "defaultModel"), "gemini-embedding-001")
            @Expect(adapterJson.get("allowExplicitWhenConfiguredAuto").getOrThrow().asBool().getValue(), false)
            @Expect(adapterJson.get("outputDimensionality").getOrThrow().asInt().getValue(), 3072)
            @Expect(adapterJson.get("batchEmbedSupported").getOrThrow().asBool().getValue(), true)
            @Expect(adapterJson.get("maxInputTokens").isNone(), true)
            let createJson = json.get("embeddingProviderCreate").getOrThrow().asObject()
            let providerJson = createJson.get("provider").getOrThrow().asObject()
            let runtimeJson = createJson.get("runtime").getOrThrow().asObject()
            @Expect(memoryRuntimeTestString(providerJson, "id"), "gemini")
            @Expect(memoryRuntimeTestString(providerJson, "model"), "gemini-embedding-001")
            @Expect(memoryRuntimeTestString(runtimeJson, "id"), "gemini")
            @Expect(runtimeJson.get("batchEmbedSupported").getOrThrow().asBool().getValue(), true)
            let runtimeSurfaceJson = json.get("embeddingProviderRuntime").getOrThrow().asObject()
            @Expect(memoryRuntimeTestString(runtimeSurfaceJson, "id"), "gemini")
            @Expect(runtimeSurfaceJson.get("batchEmbedSupported").getOrThrow().asBool().getValue(), true)
            let runtimeCacheKey = runtimeSurfaceJson.get("cacheKeyData").getOrThrow().asObject()
            @Expect(memoryRuntimeTestString(runtimeCacheKey, "providerId"), "gemini")
            @Expect(memoryRuntimeTestString(runtimeCacheKey, "model"), "gemini-embedding-001")
            let diagnosticsJson = json.get("embeddingProviderDiagnostics").getOrThrow().asObject()
            @Expect(diagnosticsJson.get("continueAutoSelection").getOrThrow().asBool().getValue(), false)
            let registrationMetadata = json.get("registrationMetadata").getOrThrow().asObject()
            @Expect(memoryRuntimeTestString(registrationMetadata, "memoryEmbeddingProviderId"), "gemini")
            @Expect(memoryRuntimeTestString(registrationMetadata, "memoryEmbeddingProviderOwnerPluginId"), "memory-core")
            @Expect(registrationMetadata.get("memoryEmbeddingProviderAllowExplicitWhenConfiguredAuto").getOrThrow().asBool().getValue(), false)
            @Expect(registrationMetadata.get("memoryEmbeddingProviderBatchEmbedSupported").getOrThrow().asBool().getValue(), true)
            @Expect(registrationMetadata.get("memoryEmbeddingProviderContinueAutoSelection").getOrThrow().asBool().getValue(), false)
            let capabilities = json.get("capabilities").getOrThrow().asObject()
            @Expect(capabilities.get("hasEmbeddingProviderRuntime").getOrThrow().asBool().getValue(), true)
            @Expect(capabilities.get("embeddingProviderAllowExplicitWhenConfiguredAuto").getOrThrow().asBool().getValue(), false)
            @Expect(capabilities.get("embeddingProviderBatchEmbedSupported").getOrThrow().asBool().getValue(), true)
        } finally {
            memoryRuntimeTestRestoreConfigText(previousConfig)
        }
    }
    */

    @TestCase
    public func autoEmbeddingProviderSelectionUsesHighestPriorityAdapter(): Unit {
        let previousConfig = memoryRuntimeTestReadConfigText()
        try {
            let root = JsonObject()
            let agents = JsonObject()
            let defaults = JsonObject()
            let memorySearch = JsonObject()
            memorySearch.put("provider", JsonString("auto"))
            defaults.put("memorySearch", memorySearch)
            agents.put("defaults", defaults)
            root.put("agents", agents)
            MetisConfigManager.writeRoot(root)

            let resolved = MemoryRuntimeRegistry.resolveBackendConfig(agentId: "general", purpose: "tool-search")
            let json = resolved.toJsonObject()
            @Expect(resolved.embeddingProviderId, "local")
            @Expect(resolved.embeddingProviderTransport, "local")
            let adapterJson = json.get("embeddingProvider").getOrThrow().asObject()
            @Expect(memoryRuntimeTestString(adapterJson, "id"), "local")
            @Expect(memoryRuntimeTestString(adapterJson, "transport"), "local")
            let createJson = json.get("embeddingProviderCreate").getOrThrow().asObject()
            let providerJson = createJson.get("provider").getOrThrow().asObject()
            @Expect(memoryRuntimeTestString(providerJson, "id"), "local")
        } finally {
            memoryRuntimeTestRestoreConfigText(previousConfig)
        }
    }

    @TestCase
    public func multimodalRequiresProviderAdapterSupport(): Unit {
        let previousConfig = memoryRuntimeTestReadConfigText()
        try {
            let root = JsonObject()
            let agents = JsonObject()
            let defaults = JsonObject()
            let memorySearch = JsonObject()
            memorySearch.put("provider", JsonString("openai"))
            let multimodal = JsonObject()
            multimodal.put("enabled", true.toJsonValue())
            memorySearch.put("multimodal", multimodal)
            defaults.put("memorySearch", memorySearch)
            agents.put("defaults", defaults)
            root.put("agents", agents)
            MetisConfigManager.writeRoot(root)

            let resolved = MemoryRuntimeRegistry.resolveBackendConfig(agentId: "general", purpose: "tool-search")
            let validation = resolved.toJsonObject().get("configValidation").getOrThrow().asObject()
            @Expect(validation.get("valid").getOrThrow().asBool().getValue(), false)
            @Expect(
                memoryRuntimeTestIssueContains(
                    validation.get("issues").getOrThrow(),
                    "requires a provider adapter that supports multimodal embeddings"
                ),
                true
            )
        } finally {
            memoryRuntimeTestRestoreConfigText(previousConfig)
        }
    }

    @TestCase
    public func multimodalRejectsFallbackProvider(): Unit {
        let previousConfig = memoryRuntimeTestReadConfigText()
        try {
            let root = JsonObject()
            let agents = JsonObject()
            let defaults = JsonObject()
            let memorySearch = JsonObject()
            memorySearch.put("provider", JsonString("gemini"))
            memorySearch.put("fallback", JsonString("local"))
            let multimodal = JsonObject()
            multimodal.put("enabled", true.toJsonValue())
            memorySearch.put("multimodal", multimodal)
            defaults.put("memorySearch", memorySearch)
            agents.put("defaults", defaults)
            root.put("agents", agents)
            MetisConfigManager.writeRoot(root)

            let resolved = MemoryRuntimeRegistry.resolveBackendConfig(agentId: "general", purpose: "tool-search")
            let validation = resolved.toJsonObject().get("configValidation").getOrThrow().asObject()
            @Expect(validation.get("valid").getOrThrow().asBool().getValue(), false)
            @Expect(
                memoryRuntimeTestIssueContains(
                    validation.get("issues").getOrThrow(),
                    "does not support memorySearch.fallback"
                ),
                true
            )
        } finally {
            memoryRuntimeTestRestoreConfigText(previousConfig)
        }
    }

    /*
    @TestCase
    public func selectedMemoryPluginWithoutRuntimeBridgeIsUnavailable(): Unit {
        let previousConfig = memoryRuntimeTestReadConfigText()
        try {
            let root = JsonObject()
            let plugins = JsonObject()
            let slots = JsonObject()
            slots.put("memory", JsonString("memory-honcho"))
            plugins.put("slots", slots)
            root.put("plugins", plugins)
            MetisConfigManager.writeRoot(root)

            let summary = MemoryRuntimeRegistry.activeMemoryPluginSummary(
                agentId: "general",
                purpose: "tool-search"
            )
            let resolved = MemoryRuntimeRegistry.resolveBackendConfig(
                agentId: "general",
                purpose: "tool-search"
            )
            @Expect(memoryRuntimeTestString(summary, "pluginId"), "memory-honcho")
            @Expect(memoryRuntimeTestString(summary, "runtimeBridge"), "unavailable")
            @Expect(summary.get("enabled").getOrThrow().asBool().getValue(), true)
            @Expect(summary.get("compatNote").isSome(), false)
            @Expect(resolved.memoryPluginId, "memory-honcho")
            @Expect(resolved.memoryPluginAvailable, false)
            @Expect(resolved.configScope, "plugins.slots.memory")
            @Expect(resolved.providerId, "")
            @Expect(resolved.backend, "")
        } finally {
            memoryRuntimeTestRestoreConfigText(previousConfig)
        }
    }
    */

    @TestCase
    public func memoryStateStatusJsonIncludesResolvedBackendConfig(): Unit {
        let status = JsonValue.fromStr(
            MemoryStateRegistry.statusJson(agentId: "", purpose: "status", requestedBackend: "", deep: false)
        ).asObject()
        @Expect(memoryRuntimeTestString(status, "provider").isEmpty(), false)
        @Expect(memoryRuntimeTestString(status, "backend").isEmpty(), false)
        @Expect(status.get("resolvedBackendConfig").isSome(), true)
        @Expect(status.get("backendSelection").isSome(), true)
        @Expect(status.get("agentScopedResolve").isSome(), true)
        @Expect(status.get("activeMemoryPlugin").isSome(), true)
        @Expect(status.get("availableMemoryPlugins").isSome(), true)
        @Expect(status.get("activeSearchBackend").isSome(), true)
        @Expect(status.get("availableBackends").isSome(), true)
        @Expect(status.get("availableSelectionTargets").isSome(), true)
        @Expect(status.get("activeOrchestrationBackend").isSome(), true)
        @Expect(status.get("availableOrchestrationBackends").isSome(), true)

        let resolved = status.get("resolvedBackendConfig").getOrThrow().asObject()
        @Expect(memoryRuntimeTestString(resolved, "providerId"), memoryRuntimeTestString(status, "provider"))
        @Expect(memoryRuntimeTestString(resolved, "backend"), memoryRuntimeTestString(status, "backend"))
        @Expect(memoryRuntimeTestString(resolved, "configScope"), "global")
        @Expect(memoryRuntimeTestString(resolved, "purpose").isEmpty(), false)
        @Expect(resolved.get("capabilities").isSome(), true)
        @Expect(resolved.get("backendConfig").isSome(), true)
        @Expect(resolved.get("selectionKeys").isSome(), true)
        @Expect(resolved.get("configTemplate").isSome(), true)
        @Expect(resolved.get("registrationMetadata").isSome(), true)
        @Expect(resolved.get("configValidation").isSome(), true)
        @Expect(resolved.get("configSchema").isSome(), true)
        let caps = resolved.get("capabilities").getOrThrow().asObject()
        @Expect(caps.get("supportsStatus").isSome(), true)
        @Expect(caps.get("supportsIndexSnapshot").isSome(), true)
        let backendCfg = resolved.get("backendConfig").getOrThrow().asObject()
        @Expect(memoryRuntimeTestString(backendCfg, "indexPath").isEmpty(), false)
    }

    @TestCase
    public func memoryStateStatusSurfacesUnavailablePluginSlot(): Unit {
        let previousConfig = memoryRuntimeTestReadConfigText()
        try {
            let root = JsonObject()
            let plugins = JsonObject()
            let slots = JsonObject()
            slots.put("memory", JsonString("none"))
            plugins.put("slots", slots)
            root.put("plugins", plugins)
            MetisConfigManager.writeRoot(root)

            let status = JsonValue.fromStr(
                MemoryStateRegistry.statusJson(agentId: "general", purpose: "dashboard-status", deep: true)
            ).asObject()
            @Expect(memoryRuntimeTestString(status, "status"), "unavailable")
            @Expect(memoryRuntimeTestString(status, "error"), "memory plugin unavailable")
            @Expect(status.get("activeMemoryPlugin").isSome(), true)

            let statusText = MemoryStateRegistry.statusText(agentId: "general", purpose: "dashboard-status", deep: true)
            @Expect(statusText.contains("Memory status: unavailable"), true)
            @Expect(statusText.contains("Active memory plugin: none"), true)
        } finally {
            memoryRuntimeTestRestoreConfigText(previousConfig)
        }
    }

    @TestCase
    public func memoryStateActionsReturnUnavailableWhenPluginSlotDisabled(): Unit {
        let previousConfig = memoryRuntimeTestReadConfigText()
        try {
            let root = JsonObject()
            let plugins = JsonObject()
            let slots = JsonObject()
            slots.put("memory", JsonString("none"))
            plugins.put("slots", slots)
            root.put("plugins", plugins)
            MetisConfigManager.writeRoot(root)

            @Expect(
                MemoryStateRegistry.fixArtifacts(agentId: "", purpose: "fix-artifacts"),
                "fix artifacts: memory plugin unavailable"
            )
            @Expect(
                MemoryStateRegistry.writeIndexSnapshot(agentId: "", purpose: "write-index-snapshot"),
                "write index snapshot: memory plugin unavailable"
            )
            @Expect(
                MemoryStateRegistry.forceReindex(agentId: "", purpose: "force-reindex"),
                "force reindex: memory plugin unavailable"
            )
            @Expect(MemoryRuntime.previewPromote(), "preview promote: memory plugin unavailable")
            @Expect(MemoryRuntime.previewPromoteJson(), "preview promote json: memory plugin unavailable")
            @Expect(MemoryRuntime.explainPromote("top"), "explain promote: memory plugin unavailable")
            @Expect(MemoryRuntime.applyPromote(), "apply promote: memory plugin unavailable")
            @Expect(MemoryRuntime.previewRemHarness(), "preview rem harness: memory plugin unavailable")
            @Expect(MemoryRuntime.applyRemHarness(), "apply rem harness: memory plugin unavailable")
            @Expect(MemoryRuntime.applyLightDreaming(), "apply light dreaming: memory plugin unavailable")
            @Expect(MemoryRuntime.applyDeepDreaming(), "apply deep dreaming: memory plugin unavailable")
            @Expect(MemoryRuntime.applyDreamingSweep(), "apply dreaming sweep: memory plugin unavailable")
        } finally {
            memoryRuntimeTestRestoreConfigText(previousConfig)
        }
    }

    @TestCase
    public func registeredBackendSummariesExposeSearchCapabilities(): Unit {
        let summaries = MemoryRuntimeRegistry.registeredBackendSummaries()
        @Expect(summaries.size() > 0, true)
        let first = summaries[0].asObject()
        @Expect(memoryRuntimeTestString(first, "providerId").isEmpty(), false)
        @Expect(memoryRuntimeTestString(first, "backend").isEmpty(), false)
        @Expect(first.get("searchEnabled").isSome(), true)
        @Expect(first.get("manualReindexSupported").isSome(), true)
        @Expect(first.get("active").isSome(), true)
        @Expect(first.get("matchesRequested").isSome(), true)
        @Expect(first.get("capabilities").isSome(), true)
        @Expect(first.get("backendConfig").isSome(), true)
        @Expect(first.get("selectionKeys").isSome(), true)
        @Expect(first.get("configTemplate").isSome(), true)
        @Expect(first.get("registrationMetadata").isSome(), true)
        @Expect(first.get("configValidation").isSome(), true)
        @Expect(first.get("configSchema").isSome(), true)
        let caps = first.get("capabilities").getOrThrow().asObject()
        @Expect(caps.get("supportsStatus").isSome(), true)
        @Expect(caps.get("supportsOrchestration").isSome(), true)
    }

    @TestCase
    public func registeredBackendSelectionTargetsExposeKeys(): Unit {
        let targets = MemoryRuntimeRegistry.registeredBackendSelectionTargets()
        @Expect(targets.size() > 0, true)
        let first = targets[0].asObject()
        @Expect(memoryRuntimeTestString(first, "key").isEmpty(), false)
        @Expect(memoryRuntimeTestString(first, "providerId").isEmpty(), false)
        @Expect(memoryRuntimeTestString(first, "backend").isEmpty(), false)
        @Expect(first.get("selectionMode").isSome(), true)
        @Expect(first.get("active").isSome(), true)
        @Expect(first.get("matchesRequested").isSome(), true)
        @Expect(first.get("capabilities").isSome(), true)
        @Expect(first.get("backendConfig").isSome(), true)
        @Expect(first.get("selectionKeys").isSome(), true)
        @Expect(first.get("configTemplate").isSome(), true)
        @Expect(first.get("registrationMetadata").isSome(), true)
        @Expect(first.get("configValidation").isSome(), true)
        @Expect(first.get("configSchema").isSome(), true)
    }

    @TestCase
    public func registeredBackendSelectionKeysExposeProviderAndBackendIds(): Unit {
        let keys = MemoryRuntimeRegistry.registeredBackendSelectionKeys()
        @Expect(keys.size > 0, true)
        var sawLocalProvider = false
        var sawLocalBackend = false
        for (key in keys) {
            if (key == "local") {
                sawLocalProvider = true
            }
            if (key == "sqlite-fts+local-file") {
                sawLocalBackend = true
            }
        }
        @Expect(sawLocalProvider, true)
        @Expect(sawLocalBackend, true)
    }

    @TestCase
    public func registeredOrchestrationBackendSummariesExposeActiveState(): Unit {
        let summaries = MemoryRuntimeRegistry.registeredOrchestrationBackendSummaries()
        @Expect(summaries.size() > 0, true)
        let first = summaries[0].asObject()
        @Expect(memoryRuntimeTestString(first, "backendId").isEmpty(), false)
        @Expect(first.get("active").isSome(), true)
        @Expect(first.get("capabilities").isSome(), true)
        let caps = first.get("capabilities").getOrThrow().asObject()
        @Expect(caps.get("supportsPromote").isSome(), true)
        @Expect(caps.get("supportsDreaming").isSome(), true)
    }

    @TestCase
    public func activeOrchestrationBackendSummaryPreservesPurpose(): Unit {
        let summary = MemoryRuntimeRegistry.activeOrchestrationBackendSummary(
            agentId: "general",
            purpose: "dashboard-status"
        )
        @Expect(memoryRuntimeTestString(summary, "backendId").isEmpty(), false)
        @Expect(memoryRuntimeTestString(summary, "agentId"), "general")
        @Expect(memoryRuntimeTestString(summary, "purpose"), "dashboard-status")
        @Expect(summary.get("capabilities").isSome(), true)
    }

    @TestCase
    public func activeSearchBackendSummaryPreservesPurpose(): Unit {
        let summary = MemoryRuntimeRegistry.activeSearchBackendSummary(
            agentId: "general",
            purpose: "dashboard-status"
        )
        @Expect(memoryRuntimeTestString(summary, "providerId").isEmpty(), false)
        @Expect(memoryRuntimeTestString(summary, "backend").isEmpty(), false)
        @Expect(memoryRuntimeTestString(summary, "agentId"), "general")
        @Expect(memoryRuntimeTestString(summary, "purpose"), "dashboard-status")
        @Expect(summary.get("capabilities").isSome(), true)
        @Expect(summary.get("backendConfig").isSome(), true)
        @Expect(summary.get("selectionKeys").isSome(), true)
        @Expect(summary.get("configTemplate").isSome(), true)
        @Expect(summary.get("registrationMetadata").isSome(), true)
        @Expect(summary.get("configValidation").isSome(), true)
        @Expect(summary.get("configSchema").isSome(), true)
    }

    @TestCase
    public func backendSelectionSummaryPreservesPurpose(): Unit {
        let summary = MemoryRuntimeRegistry.backendSelectionSummary(
            agentId: "general",
            purpose: "dashboard-status"
        )
        @Expect(memoryRuntimeTestString(summary, "selectedProviderId").isEmpty(), false)
        @Expect(memoryRuntimeTestString(summary, "selectedBackend").isEmpty(), false)
        @Expect(memoryRuntimeTestString(summary, "agentId"), "general")
        @Expect(memoryRuntimeTestString(summary, "purpose"), "dashboard-status")
        @Expect(memoryRuntimeTestString(summary, "selectionMode").isEmpty(), false)
    }

    @TestCase
    public func agentScopedResolveSummaryPreservesPurposeAndInheritance(): Unit {
        let summary = MemoryRuntimeRegistry.agentScopedResolveSummary(
            agentId: "general",
            purpose: "dashboard-status"
        )
        @Expect(memoryRuntimeTestString(summary, "agentId"), "general")
        @Expect(memoryRuntimeTestString(summary, "purpose"), "dashboard-status")
        @Expect(memoryRuntimeTestString(summary, "configScope"), "global")
        @Expect(summary.get("inheritsGlobal").getOrThrow().asBool().getValue(), true)
        @Expect(memoryRuntimeTestString(summary, "scopeSource"), "memory.backend")
        @Expect(memoryRuntimeTestString(summary, "resolvedProviderId").isEmpty(), false)
        @Expect(memoryRuntimeTestString(summary, "resolvedBackend").isEmpty(), false)
        @Expect(summary.get("resolvedBackendConfig").isSome(), true)
    }

    @TestCase
    public func previewBackendSelectionSummaryAcceptsBackendId(): Unit {
        let summary = MemoryRuntimeRegistry.previewBackendSelectionSummary(
            "sqlite-fts+local-file",
            agentId: "general",
            purpose: "preview-selection"
        )
        @Expect(summary.get("matched").getOrThrow().asBool().getValue(), true)
        @Expect(memoryRuntimeTestString(summary, "selectedProviderId"), "local")
        @Expect(memoryRuntimeTestString(summary, "selectedBackend"), "sqlite-fts+local-file")
        @Expect(memoryRuntimeTestString(summary, "selectionMode"), "backend-id")
        @Expect(memoryRuntimeTestString(summary, "agentId"), "general")
        @Expect(memoryRuntimeTestString(summary, "purpose"), "preview-selection")
        @Expect(summary.get("resolvedBackendConfig").isSome(), true)
    }

    @TestCase
    public func previewBackendSelectionSummaryReportsMiss(): Unit {
        let summary = MemoryRuntimeRegistry.previewBackendSelectionSummary(
            "missing-backend",
            agentId: "general",
            purpose: "preview-selection"
        )
        @Expect(summary.get("matched").getOrThrow().asBool().getValue(), false)
        @Expect(memoryRuntimeTestString(summary, "selectedProviderId"), "")
        @Expect(memoryRuntimeTestString(summary, "selectedBackend"), "")
    }

    @TestCase
    public func previewAgentScopedResolveSummaryAcceptsOverride(): Unit {
        let summary = MemoryRuntimeRegistry.previewAgentScopedResolveSummary(
            "sqlite-fts+local-file",
            agentId: "general",
            purpose: "dashboard-status"
        )
        @Expect(summary.get("matched").getOrThrow().asBool().getValue(), true)
        @Expect(memoryRuntimeTestString(summary, "agentId"), "general")
        @Expect(memoryRuntimeTestString(summary, "purpose"), "dashboard-status")
        @Expect(memoryRuntimeTestString(summary, "configScope"), "agent-override-preview")
        @Expect(summary.get("inheritsGlobal").getOrThrow().asBool().getValue(), false)
        @Expect(memoryRuntimeTestString(summary, "scopeSource"), "agent.memory.backend")
        @Expect(memoryRuntimeTestString(summary, "selectedProviderId"), "local")
        @Expect(memoryRuntimeTestString(summary, "selectedBackend"), "sqlite-fts+local-file")
        @Expect(summary.get("resolvedBackendConfig").isSome(), true)
    }

    @TestCase
    public func previewAgentScopedResolveSummaryFallsBackToGlobalOnMiss(): Unit {
        let summary = MemoryRuntimeRegistry.previewAgentScopedResolveSummary(
            "missing-backend",
            agentId: "general",
            purpose: "dashboard-status"
        )
        @Expect(summary.get("matched").getOrThrow().asBool().getValue(), false)
        @Expect(memoryRuntimeTestString(summary, "agentId"), "general")
        @Expect(memoryRuntimeTestString(summary, "purpose"), "dashboard-status")
        @Expect(memoryRuntimeTestString(summary, "configScope"), "global")
        @Expect(summary.get("inheritsGlobal").getOrThrow().asBool().getValue(), true)
        @Expect(memoryRuntimeTestString(summary, "scopeSource"), "memory.backend")
        @Expect(memoryRuntimeTestString(summary, "selectedProviderId").isEmpty(), false)
        @Expect(memoryRuntimeTestString(summary, "selectedBackend").isEmpty(), false)
        @Expect(summary.get("resolvedBackendConfig").isSome(), true)
    }

    @TestCase
    public func memoryStateStatusJsonPreservesExplicitPurpose(): Unit {
        let status = JsonValue.fromStr(
            MemoryStateRegistry.statusJson(purpose: "dashboard-status", deep: true)
        ).asObject()
        let resolved = status.get("resolvedBackendConfig").getOrThrow().asObject()
        @Expect(memoryRuntimeTestString(resolved, "purpose"), "dashboard-status")
    }

    @TestCase
    public func memoryStatePreviewStatusJsonIncludesPreviewSurfaces(): Unit {
        let status = JsonValue.fromStr(
            MemoryStateRegistry.statusJson(
                agentId: "general",
                purpose: "dashboard-status",
                requestedBackend: "sqlite-fts+local-file",
                deep: true
            )
        ).asObject()
        @Expect(status.get("previewBackendSelection").isSome(), true)
        @Expect(status.get("previewAgentScopedResolve").isSome(), true)
        @Expect(status.get("previewResolvedBackendConfig").isSome(), true)
        let preview = status.get("previewBackendSelection").getOrThrow().asObject()
        @Expect(memoryRuntimeTestString(preview, "selectedProviderId"), "local")
        @Expect(memoryRuntimeTestString(preview, "selectedBackend"), "sqlite-fts+local-file")
    }

    @TestCase
    public func resolveMemoryRuntimeHelpersPreserveExplicitPurpose(): Unit {
        let resolved = MemoryRuntime.resolveResolvedBackendConfig(agentId: "general", purpose: "tool-resolve-files")
        @Expect(resolved.agentId, "general")
        @Expect(resolved.purpose, "tool-resolve-files")

        let statusText = MemoryStateRegistry.statusText(agentId: "general", purpose: "force-reindex")
        @Expect(statusText.contains("Resolved purpose: force-reindex"), true)
        @Expect(statusText.contains("Resolved agentId: general"), true)
        @Expect(statusText.contains("Requested backend: "), true)
        @Expect(statusText.contains("Selection mode: "), true)
        @Expect(statusText.contains("Scope source: memory.backend"), true)
        @Expect(statusText.contains("Inherits global: true"), true)
        let previewText = MemoryStateRegistry.statusText(
            agentId: "general",
            purpose: "dashboard-status",
            requestedBackend: "sqlite-fts+local-file",
            deep: true
        )
        @Expect(previewText.contains("Preview requested backend: sqlite-fts+local-file"), true)
        @Expect(previewText.contains("Preview matched: true"), true)
        @Expect(previewText.contains("Preview selected providerId: local"), true)
    }

    @TestCase
    public func localMemoryIndexStatusPreservesExplicitPurpose(): Unit {
        let status = JsonValue.fromStr(
            LocalMemoryIndexManager.buildStatusJson(agentId: "general", purpose: "provider-status", deep: false)
        ).asObject()
        let resolved = status.get("resolvedBackendConfig").getOrThrow().asObject()
        @Expect(memoryRuntimeTestString(resolved, "agentId"), "general")
        @Expect(memoryRuntimeTestString(resolved, "purpose"), "provider-status")
    }

    @TestCase
    public func activeBackendResolveSurfaceAcceptsExplicitPurpose(): Unit {
        let searchBackend = MemoryRuntimeRegistry.activeSearchBackend(agentId: "general", purpose: "dashboard-status")
        @Expect(searchBackend.providerId().isEmpty(), false)
        let resolved = MemoryRuntimeRegistry.resolveBackendConfig(agentId: "general", purpose: "dashboard-status")
        let _ = MemoryRuntimeRegistry.activeOrchestrationBackend(
            agentId: resolved.agentId,
            purpose: resolved.purpose
        )
        @Expect(resolved.purpose, "dashboard-status")
    }

    @TestCase
    public func qmdResolvedBackendConfigCarriesBackendSpecificSummary(): Unit {
        let previousProvider = CliConfig.memoryProvider
        let previousCommand = CliConfig.qmdCommand
        try {
            MemoryRuntimeRegistry.activateBackend("qmd", startMaintenance: false)
            CliConfig.qmdCommand = "qmd"
            let resolved = MemoryRuntimeRegistry.resolveBackendConfig(agentId: "general", purpose: "tool-search")
            let json = resolved.toJsonObject()
            let backendCfg = json.get("backendConfig").getOrThrow().asObject()
            let template = json.get("configTemplate").getOrThrow().asObject()
            let registration = json.get("registrationMetadata").getOrThrow().asObject()
            let validation = json.get("configValidation").getOrThrow().asObject()
            let schema = json.get("configSchema").getOrThrow().asObject()
            @Expect(memoryRuntimeTestString(json, "backend"), "qmd")
            @Expect(backendCfg.get("qmd").isSome(), true)
            @Expect(template.get("memory").isSome(), true)
            @Expect(registration.get("requiresCommandConfig").isSome(), true)
            @Expect(registration.get("requiresPathConfig").isSome(), true)
            @Expect(validation.get("valid").isSome(), true)
            @Expect(validation.get("issues").isSome(), true)
            @Expect(schema.get("requiredKeys").isSome(), true)
            @Expect(schema.get("optionalKeys").isSome(), true)
            let qmd = backendCfg.get("qmd").getOrThrow().asObject()
            @Expect(memoryRuntimeTestString(qmd, "command"), "qmd")
            @Expect(memoryRuntimeTestString(qmd, "searchMode"), CliConfig.qmdSearchMode)
            let requiredKeys = schema.get("requiredKeys").getOrThrow().asArray()
            var sawQmdCommand = false
            for (i in 0..requiredKeys.size()) {
                if (requiredKeys[i].asString().getValue() == "memory.qmd.command") {
                    sawQmdCommand = true
                    break
                }
            }
            @Expect(sawQmdCommand, true)
            let caps = json.get("capabilities").getOrThrow().asObject()
            @Expect(caps.get("supportsBackgroundMaintenance").isSome(), true)
            @Expect(caps.get("supportsPathCollections").isSome(), true)
        } finally {
            MemoryRuntimeRegistry.activateBackend(previousProvider, startMaintenance: false)
            CliConfig.qmdCommand = previousCommand
        }
    }

    @TestCase
    public func activateBackendAcceptsBackendIdSelection(): Unit {
        let previousProvider = CliConfig.memoryProvider
        try {
            let ok = MemoryRuntimeRegistry.activateBackend("sqlite-fts+local-file", startMaintenance: false)
            @Expect(ok, true)
            @Expect(MemoryRuntimeRegistry.activeProviderName(), "local")
            let summary = MemoryRuntimeRegistry.backendSelectionSummary(
                agentId: "general",
                purpose: "dashboard-status"
            )
            @Expect(memoryRuntimeTestString(summary, "selectionMode"), "backend-id")
            @Expect(memoryRuntimeTestString(summary, "selectedProviderId"), "local")
            @Expect(memoryRuntimeTestString(summary, "selectedBackend"), "sqlite-fts+local-file")
            let backends = MemoryRuntimeRegistry.registeredBackendSummaries()
            var sawActiveRequested = false
            for (i in 0..backends.size()) {
                let obj = backends[i].asObject()
                if (
                    memoryRuntimeTestString(obj, "providerId") == "local" &&
                    memoryRuntimeTestString(obj, "backend") == "sqlite-fts+local-file"
                ) {
                    @Expect(obj.get("active").getOrThrow().asBool().getValue(), true)
                    @Expect(obj.get("matchesRequested").getOrThrow().asBool().getValue(), true)
                    sawActiveRequested = true
                    break
                }
            }
            @Expect(sawActiveRequested, true)
        } finally {
            MemoryRuntimeRegistry.activateBackend(previousProvider, startMaintenance: false)
        }
    }

    @TestCase
    public func resolveBackendConfigSupportsAgentManifestOverride(): Unit {
        let previousProvider = CliConfig.memoryProvider
        let root = CliConfig.dotDir.join("phase_d_memory_agent_override_test")
        let agentId = "phase-d-memory-agent"
        let agentDir = root.join(agentId)
        let manifest = agentDir.join("AGENT.md")
        try {
            if (exists(root)) {
                remove(root, recursive: true)
            }
            Directory.create(agentDir, recursive: true)
            File.writeTo(
                manifest,
                (
                    "name: Phase D Memory Agent\n" +
                    "memoryBackend: qmd\n" +
                    "---\n" +
                    "# Phase D Memory Agent\n"
                ).toArray()
            )
            CliConfig.subagentDirs.add(root)
            MemoryRuntimeRegistry.activateBackend("local", startMaintenance: false)

            let resolved = MemoryRuntimeRegistry.resolveBackendConfig(
                agentId: agentId,
                purpose: "tool-search"
            )
            @Expect(resolved.configScope, "agent-manifest")
            @Expect(resolved.providerId, "qmd")
            @Expect(resolved.backend, "qmd")

            let backend = MemoryRuntimeRegistry.activeSearchBackend(
                agentId: agentId,
                purpose: "tool-search"
            )
            @Expect(backend.providerId(), "qmd")
        } finally {
            MemoryRuntimeRegistry.activateBackend(previousProvider, startMaintenance: false)
            if (exists(root)) {
                remove(root, recursive: true)
            }
        }
    }
}
