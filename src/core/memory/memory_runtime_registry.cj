package metis.core.memory

import metis.core.config.CliConfig
import metis.core.config.MetisConfigManager
import metis.utils.loadMarkdown
import magic.jsonable.*
import std.collection.ArrayList
import std.fs.exists
import stdx.encoding.json.{JsonArray, JsonFloat, JsonInt, JsonObject, JsonString}

private class MemorySearchConfigSelection {
    public let requestedBackend: String
    public let configScope: String
    public let enabled: Bool

    public init(requestedBackend: String, configScope: String, enabled: Bool) {
        this.requestedBackend = requestedBackend.trimAscii()
        this.configScope = configScope.trimAscii()
        this.enabled = enabled
    }
}

private func memorySearchJsonString(obj: JsonObject, key: String, fallback!: String = ""): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue().trimAscii() } catch (_: Exception) { fallback }
        case None => fallback
    }
}

private func memorySearchJsonStringArray(obj: JsonObject, key: String): Array<String> {
    match (obj.get(key)) {
        case Some(v) =>
            try {
                let arr = v.asArray()
                let out = ArrayList<String>()
                for (item in arr.getItems()) {
                    try {
                        let text = item.asString().getValue().trimAscii()
                        if (!text.isEmpty()) {
                            out.add(text)
                        }
                    } catch (_: Exception) {
                        ()
                    }
                }
                out.toArray()
            } catch (_: Exception) {
                Array<String>()
            }
        case None => Array<String>()
    }
}

private func memoryRuntimeEmbeddingProviderFields(
    providerId: String,
    agentId: String
): (String, String, String, String, Bool, Bool, Bool) {
    match (resolveMemoryEmbeddingProviderAdapter(providerId, agentId: agentId)) {
        case Some(adapter) =>
            let ownerAndRegistered = match (getRegisteredMemoryEmbeddingProvider(adapter.id)) {
                case Some(entry) => (entry.ownerPluginId, true)
                case None =>
                    match (getMemoryEmbeddingCapabilityProvider(adapter.id)) {
                        case Some(entry) => (entry.ownerPluginId, false)
                        case None => ("", false)
                    }
            }
            (
                adapter.id,
                adapter.transport,
                adapter.defaultModel,
                ownerAndRegistered[0],
                ownerAndRegistered[1],
                adapter.supportsMultimodalEmbeddings,
                adapter.allowExplicitWhenConfiguredAuto
            )
        case None => ("", "", "", "", false, false, false)
    }
}

/**
 * Legacy-style runtime facade for memory backend resolution and manager
 * lifecycle. The underlying provider registry still owns concrete adapters,
 * while this registry becomes the single runtime surface for gateway/CLI code.
 */
public class MemoryRuntimeRegistry {
    private static let DEFAULT_MEMORY_PLUGIN_ID = "memory-core"

    private static func memoryRuntimeRegistryJsonString(obj: JsonObject, key: String): String {
        match (obj.get(key)) {
            case Some(v) =>
                try { v.asString().getValue().trimAscii() } catch (_: Exception) { "" }
            case None => ""
        }
    }

    private static func resolvedSearchModeForBackend(backend: String): String {
        if (backend == "qmd") {
            return CliConfig.qmdSearchMode.trimAscii()
        }
        if (backend.contains("sqlite-fts")) {
            return "fts5"
        }
        if (backend == "external-command") {
            return "external"
        }
        ""
    }

    private static func resolvedConfigFromBackendConfig(
        cfg: MemoryBackendConfig,
        agentId!: String = "",
        purpose!: String = "available-backend",
        configScope!: String = "global"
    ): ResolvedMemoryBackendConfig {
        let providerFields = memoryRuntimeEmbeddingProviderFields(cfg.providerId, agentId.trimAscii())
        ResolvedMemoryBackendConfig(
            cfg.providerId,
            cfg.backend,
            cfg.searchEnabled,
            cfg.manualReindexSupported,
            cfg.indexPath,
            citations: CliConfig.memoryCitations.trimAscii(),
            searchMode: resolvedSearchModeForBackend(cfg.backend),
            agentId: agentId.trimAscii(),
            purpose: if (purpose.trimAscii().isEmpty()) { "available-backend" } else { purpose.trimAscii() },
            configScope: configScope.trimAscii(),
            memoryPluginId: activeMemoryPluginId(),
            memoryPluginAvailable: memoryPluginAvailable(),
            memoryPluginSlot: "memory",
            model: resolvedMemorySearchModel(agentId.trimAscii()),
            fallbackProviderId: resolvedMemorySearchFallbackProviderId(agentId.trimAscii()),
            extraPaths: resolvedMemorySearchExtraPaths(agentId.trimAscii()),
            qmdExtraCollections: resolvedMemorySearchQmdExtraCollections(agentId.trimAscii()),
            remoteBaseUrl: resolvedMemorySearchRemoteBaseUrl(agentId.trimAscii()),
            remoteApiKey: resolvedMemorySearchRemoteApiKey(agentId.trimAscii()),
            remoteHeaders: resolvedMemorySearchRemoteHeaders(agentId.trimAscii()),
            localConfig: resolvedMemorySearchLocalConfig(agentId.trimAscii()),
            queryHybridConfig: resolvedMemorySearchQueryHybridConfig(agentId.trimAscii()),
            storeConfig: resolvedMemorySearchStoreConfig(agentId.trimAscii()),
            syncConfig: resolvedMemorySearchSyncConfig(agentId.trimAscii()),
            outputDimensionality: resolvedMemorySearchOutputDimensionality(agentId.trimAscii()),
            multimodalConfig: resolvedMemorySearchMultimodalConfig(agentId.trimAscii()),
            embeddingProviderId: providerFields[0],
            embeddingProviderTransport: providerFields[1],
            embeddingProviderDefaultModel: providerFields[2],
            embeddingProviderOwnerPluginId: providerFields[3],
            embeddingProviderRegistered: providerFields[4],
            embeddingProviderSupportsMultimodal: providerFields[5],
            embeddingProviderAllowExplicitWhenConfiguredAuto: providerFields[6]
        )
    }

    private static func unavailableResolvedConfig(
        agentId: String,
        purpose: String
    ): ResolvedMemoryBackendConfig {
        let providerFields = memoryRuntimeEmbeddingProviderFields(configuredRequestedBackend(agentId), agentId)
        ResolvedMemoryBackendConfig(
            "",
            "",
            false,
            false,
            "",
            citations: CliConfig.memoryCitations.trimAscii(),
            searchMode: "",
            agentId: agentId,
            purpose: purpose,
            configScope: "plugins.slots.memory",
            memoryPluginId: activeMemoryPluginId(),
            memoryPluginAvailable: false,
            memoryPluginSlot: "memory",
            model: resolvedMemorySearchModel(agentId),
            fallbackProviderId: resolvedMemorySearchFallbackProviderId(agentId),
            extraPaths: resolvedMemorySearchExtraPaths(agentId),
            qmdExtraCollections: resolvedMemorySearchQmdExtraCollections(agentId),
            remoteBaseUrl: resolvedMemorySearchRemoteBaseUrl(agentId),
            remoteApiKey: resolvedMemorySearchRemoteApiKey(agentId),
            remoteHeaders: resolvedMemorySearchRemoteHeaders(agentId),
            localConfig: resolvedMemorySearchLocalConfig(agentId),
            queryHybridConfig: resolvedMemorySearchQueryHybridConfig(agentId),
            storeConfig: resolvedMemorySearchStoreConfig(agentId),
            syncConfig: resolvedMemorySearchSyncConfig(agentId),
            outputDimensionality: resolvedMemorySearchOutputDimensionality(agentId),
            multimodalConfig: resolvedMemorySearchMultimodalConfig(agentId),
            embeddingProviderId: providerFields[0],
            embeddingProviderTransport: providerFields[1],
            embeddingProviderDefaultModel: providerFields[2],
            embeddingProviderOwnerPluginId: providerFields[3],
            embeddingProviderRegistered: providerFields[4],
            embeddingProviderSupportsMultimodal: providerFields[5],
            embeddingProviderAllowExplicitWhenConfiguredAuto: providerFields[6]
        )
    }

    private static func disabledResolvedConfig(
        agentId: String,
        purpose: String,
        configScope: String
    ): ResolvedMemoryBackendConfig {
        let providerFields = memoryRuntimeEmbeddingProviderFields(configuredRequestedBackend(agentId), agentId)
        ResolvedMemoryBackendConfig(
            "",
            "",
            false,
            false,
            "",
            citations: CliConfig.memoryCitations.trimAscii(),
            searchMode: "",
            agentId: agentId,
            purpose: purpose,
            configScope: configScope,
            memoryPluginId: activeMemoryPluginId(),
            memoryPluginAvailable: memoryPluginAvailable(),
            memoryPluginSlot: "memory",
            model: resolvedMemorySearchModel(agentId),
            fallbackProviderId: resolvedMemorySearchFallbackProviderId(agentId),
            extraPaths: resolvedMemorySearchExtraPaths(agentId),
            qmdExtraCollections: resolvedMemorySearchQmdExtraCollections(agentId),
            remoteBaseUrl: resolvedMemorySearchRemoteBaseUrl(agentId),
            remoteApiKey: resolvedMemorySearchRemoteApiKey(agentId),
            remoteHeaders: resolvedMemorySearchRemoteHeaders(agentId),
            localConfig: resolvedMemorySearchLocalConfig(agentId),
            queryHybridConfig: resolvedMemorySearchQueryHybridConfig(agentId),
            storeConfig: resolvedMemorySearchStoreConfig(agentId),
            syncConfig: resolvedMemorySearchSyncConfig(agentId),
            outputDimensionality: resolvedMemorySearchOutputDimensionality(agentId),
            multimodalConfig: resolvedMemorySearchMultimodalConfig(agentId),
            embeddingProviderId: providerFields[0],
            embeddingProviderTransport: providerFields[1],
            embeddingProviderDefaultModel: providerFields[2],
            embeddingProviderOwnerPluginId: providerFields[3],
            embeddingProviderRegistered: providerFields[4],
            embeddingProviderSupportsMultimodal: providerFields[5],
            embeddingProviderAllowExplicitWhenConfiguredAuto: providerFields[6]
        )
    }

    private static func orchestrationCapabilitiesJson(backendId: String): JsonObject {
        let out = JsonObject()
        let normalized = backendId.trimAscii()
        let isLocal = normalized == "local"
        out.put("supportsPromote", isLocal.toJsonValue())
        out.put("supportsRemHarness", isLocal.toJsonValue())
        out.put("supportsDreaming", isLocal.toJsonValue())
        out.put("supportsExplainPromote", isLocal.toJsonValue())
        out
    }

    private static func selectionModeForResolved(requested: String, resolved: ResolvedMemoryBackendConfig): String {
        let normalized = requested.trimAscii()
        if (normalized.isEmpty()) {
            return "default"
        }
        if (normalized == resolved.providerId) {
            return "provider-id"
        }
        if (normalized == resolved.backend) {
            return "backend-id"
        }
        "fallback"
    }

    private static func backendMatchesRequested(cfg: MemoryBackendConfig, requested: String): Bool {
        let normalized = requested.trimAscii()
        if (normalized.isEmpty()) {
            return false
        }
        normalized == cfg.providerId.trimAscii() || normalized == cfg.backend.trimAscii()
    }

    private static func configuredAgentRequestedBackend(agentId: String): String {
        let normalized = agentId.trimAscii()
        if (normalized.isEmpty()) {
            return ""
        }
        for (agentRoot in CliConfig.subagentDirs) {
            let nestedAgentDir = agentRoot.join(normalized)
            let nestedManifest = nestedAgentDir.join("AGENT.md")
            if (!exists(nestedManifest)) {
                continue
            }
            let (metadata, _content) = loadMarkdown(nestedManifest)
            for (key in ["memoryBackend", "memory_backend", "memory.backend"]) {
                let value = (metadata.get(key) ?? "").trimAscii()
                if (!value.isEmpty()) {
                    return value
                }
            }
        }
        ""
    }

    private static func configuredMemorySearchSelection(agentId: String): Option<MemorySearchConfigSelection> {
        let normalizedAgentId = agentId.trimAscii()
        let scope = MetisConfigManager.readAgentMemorySearchScope(normalizedAgentId).trimAscii()
        if (scope.isEmpty() || scope == "unconfigured") {
            return None<MemorySearchConfigSelection>
        }
        match (MetisConfigManager.readAgentMemorySearch(normalizedAgentId)) {
            case Some(cfg) =>
                let requestedBackend = memoryRuntimeRegistryJsonString(cfg, "provider")
                let enabled = match (cfg.get("enabled")) {
                    case Some(value) =>
                        try { value.asBool().getValue() } catch (_: Exception) { true }
                    case None => true
                }
                if (requestedBackend.isEmpty() && enabled) {
                    return None<MemorySearchConfigSelection>
                }
                Some(
                    MemorySearchConfigSelection(
                        requestedBackend,
                        scope,
                        enabled
                    )
                )
            case None => None<MemorySearchConfigSelection>
        }
    }

    private static func configuredMemorySearchConfig(agentId: String): Option<JsonObject> {
        MetisConfigManager.readAgentMemorySearch(agentId.trimAscii())
    }

    private static func resolvedMemorySearchFallbackProviderId(agentId: String): String {
        match (configuredMemorySearchConfig(agentId)) {
            case Some(cfg) =>
                let fallback = memorySearchJsonString(cfg, "fallback", fallback: "none")
                if (fallback.isEmpty()) { "none" } else { fallback }
            case None => "none"
        }
    }

    private static func resolvedMemorySearchModel(agentId: String): String {
        match (configuredMemorySearchConfig(agentId)) {
            case Some(cfg) => memorySearchJsonString(cfg, "model")
            case None => ""
        }
    }

    private static func resolvedMemorySearchExtraPaths(agentId: String): Array<String> {
        match (configuredMemorySearchConfig(agentId)) {
            case Some(cfg) => memorySearchJsonStringArray(cfg, "extraPaths")
            case None => Array<String>()
        }
    }

    private static func resolvedMemorySearchQmdExtraCollections(agentId: String): Array<String> {
        match (configuredMemorySearchConfig(agentId)) {
            case Some(cfg) =>
                match (cfg.get("qmd")) {
                    case Some(v) =>
                        try { memorySearchJsonStringArray(v.asObject(), "extraCollections") } catch (_: Exception) { Array<String>() }
                    case None => Array<String>()
                }
            case None => Array<String>()
        }
    }

    private static func resolvedMemorySearchRemoteBaseUrl(agentId: String): String {
        match (configuredMemorySearchConfig(agentId)) {
            case Some(cfg) =>
                match (cfg.get("remote")) {
                    case Some(v) =>
                        try { memorySearchJsonString(v.asObject(), "baseUrl") } catch (_: Exception) { "" }
                    case None => ""
                }
            case None => ""
        }
    }

    private static func resolvedMemorySearchRemoteApiKey(agentId: String): String {
        match (configuredMemorySearchConfig(agentId)) {
            case Some(cfg) =>
                match (cfg.get("remote")) {
                    case Some(v) =>
                        try { memorySearchJsonString(v.asObject(), "apiKey") } catch (_: Exception) { "" }
                    case None => ""
                }
            case None => ""
        }
    }

    private static func resolvedMemorySearchRemoteHeaders(agentId: String): JsonObject {
        match (configuredMemorySearchConfig(agentId)) {
            case Some(cfg) =>
                match (cfg.get("remote")) {
                    case Some(v) =>
                        try {
                            let remote = v.asObject()
                            match (remote.get("headers")) {
                                case Some(headers) =>
                                    try { headers.asObject() } catch (_: Exception) { JsonObject() }
                                case None => JsonObject()
                            }
                        } catch (_: Exception) {
                            JsonObject()
                        }
                    case None => JsonObject()
                }
            case None => JsonObject()
        }
    }

    private static func resolvedMemorySearchLocalConfig(agentId: String): JsonObject {
        match (configuredMemorySearchConfig(agentId)) {
            case Some(cfg) =>
                match (cfg.get("local")) {
                    case Some(v) =>
                        try { v.asObject() } catch (_: Exception) { JsonObject() }
                    case None => JsonObject()
                }
            case None => JsonObject()
        }
    }

    private static func resolvedMemorySearchQueryHybridConfig(agentId: String): JsonObject {
        match (configuredMemorySearchConfig(agentId)) {
            case Some(cfg) =>
                match (cfg.get("query")) {
                    case Some(v) =>
                        try {
                            let query = v.asObject()
                            match (query.get("hybrid")) {
                                case Some(hybrid) =>
                                    try { hybrid.asObject() } catch (_: Exception) { JsonObject() }
                                case None => JsonObject()
                            }
                        } catch (_: Exception) {
                            JsonObject()
                        }
                    case None => JsonObject()
                }
            case None => JsonObject()
        }
    }

    private static func resolvedMemorySearchStoreConfig(agentId: String): JsonObject {
        match (configuredMemorySearchConfig(agentId)) {
            case Some(cfg) =>
                match (cfg.get("store")) {
                    case Some(v) =>
                        try { v.asObject() } catch (_: Exception) { JsonObject() }
                    case None => JsonObject()
                }
            case None => JsonObject()
        }
    }

    private static func resolvedMemorySearchSyncConfig(agentId: String): JsonObject {
        match (configuredMemorySearchConfig(agentId)) {
            case Some(cfg) =>
                match (cfg.get("sync")) {
                    case Some(v) =>
                        try { v.asObject() } catch (_: Exception) { JsonObject() }
                    case None => JsonObject()
                }
            case None => JsonObject()
        }
    }

    private static func resolvedMemorySearchOutputDimensionality(agentId: String): Int64 {
        match (configuredMemorySearchConfig(agentId)) {
            case Some(cfg) =>
                match (cfg.get("outputDimensionality")) {
                    case Some(v) =>
                        match (v) {
                            case i: JsonInt => i.getValue()
                            case f: JsonFloat => Int64(f.getValue())
                            case _ => 0
                        }
                    case None => 0
                }
            case None => 0
        }
    }

    private static func resolvedMemorySearchMultimodalConfig(agentId: String): JsonObject {
        match (configuredMemorySearchConfig(agentId)) {
            case Some(cfg) =>
                match (cfg.get("multimodal")) {
                    case Some(v) =>
                        try { v.asObject() } catch (_: Exception) { JsonObject() }
                    case None => JsonObject()
                }
            case None => JsonObject()
        }
    }

    private static func configuredRequestedBackend(agentId: String): String {
        match (configuredMemorySearchSelection(agentId)) {
            case Some(selection) =>
                if (!selection.requestedBackend.isEmpty()) {
                    return selection.requestedBackend
                }
            case None => ()
        }
        let manifestBackend = configuredAgentRequestedBackend(agentId)
        if (!manifestBackend.isEmpty()) {
            return manifestBackend
        }
        CliConfig.memoryProvider.trimAscii()
    }

    private static func selectedMemoryPluginId(): String {
        let slot = MetisConfigManager.readMemoryPluginSlot().trimAscii()
        if (slot.isEmpty()) {
            return DEFAULT_MEMORY_PLUGIN_ID
        }
        slot
    }

    private static func resolvedMemoryPluginId(): String {
        let selected = selectedMemoryPluginId()
        if (selected == "none") {
            return "none"
        }
        let active = MetisConfigManager.readActiveMemoryPluginId().trimAscii()
        if (active.isEmpty()) {
            return DEFAULT_MEMORY_PLUGIN_ID
        }
        active
    }

    private static func memoryPluginRuntimeBridgeAvailable(pluginId: String): Bool {
        let normalized = pluginId.trimAscii()
        if (normalized.isEmpty() || normalized == "none") {
            return false
        }
        if (normalized == DEFAULT_MEMORY_PLUGIN_ID) {
            initializeBuiltinMemoryPluginState()
        }
        hasMemoryRuntime()
    }

    private static func memoryPluginPromptSectionRegistered(pluginId: String): Bool {
        let normalized = pluginId.trimAscii()
        if (normalized.isEmpty() || normalized == "none") {
            return false
        }
        if (normalized == DEFAULT_MEMORY_PLUGIN_ID) {
            initializeBuiltinMemoryPluginState()
        }
        getMemoryPromptSectionBuilder().isSome()
    }

    private static func memoryPluginFlushPlanRegistered(pluginId: String): Bool {
        let normalized = pluginId.trimAscii()
        if (normalized.isEmpty() || normalized == "none") {
            return false
        }
        if (normalized == DEFAULT_MEMORY_PLUGIN_ID) {
            initializeBuiltinMemoryPluginState()
        }
        getMemoryFlushPlanResolver().isSome()
    }

    private static func memoryPluginSummaryRow(
        pluginId: String,
        selectedId: String,
        activeId: String
    ): JsonObject {
        let normalized = pluginId.trimAscii()
        let row = JsonObject()
        row.put("pluginId", JsonString(normalized))
        row.put("selected", (normalized == selectedId).toJsonValue())
        row.put("active", (normalized == activeId).toJsonValue())
        row.put("kind", JsonString("memory"))
        row.put("slot", JsonString("memory"))
        row.put("configScope", JsonString("plugins.slots.memory"))
        let runtimeRegistered = memoryPluginRuntimeBridgeAvailable(normalized)
        let promptRegistered = memoryPluginPromptSectionRegistered(normalized)
        let flushRegistered = memoryPluginFlushPlanRegistered(normalized)
        row.put("ownsRuntime", runtimeRegistered.toJsonValue())
        row.put("registersPromptSection", promptRegistered.toJsonValue())
        row.put("registersFlushPlan", flushRegistered.toJsonValue())
        row.put("registersRuntimeAdapter", runtimeRegistered.toJsonValue())
        row.put(
            "runtimeBridge",
            JsonString(
                if (normalized == "none") {
                    "disabled"
                } else if (runtimeRegistered) {
                    "registered-memory-runtime"
                } else {
                    "unavailable"
                }
            )
        )
        row.put("enabled", MetisConfigManager.readMemoryPluginEnabled(normalized).toJsonValue())
        match (MetisConfigManager.readMemoryPluginConfig(normalized)) {
            case Some(cfg) => row.put("config", cfg)
            case None => ()
        }
        if (runtimeRegistered || promptRegistered || flushRegistered) {
            row.put("compatNote", JsonString("M4 bridge: memory-core registrations now flow through a memory plugin state registry, while concrete search/orchestration still delegates to the built-in memory runtime facade."))
        }
        row
    }

    public static func activeMemoryPluginId(): String {
        resolvedMemoryPluginId()
    }

    public static func memoryPluginAvailable(): Bool {
        memoryPluginRuntimeBridgeAvailable(activeMemoryPluginId())
    }

    public static func memoryPluginUnavailableError(): String {
        "memory plugin unavailable"
    }

    public static func registeredMemoryPluginSummaries(): JsonArray {
        let out = JsonArray([])
        let selected = selectedMemoryPluginId()
        let active = resolvedMemoryPluginId()
        let seen = ArrayList<String>()
        for (pluginId in ["none", DEFAULT_MEMORY_PLUGIN_ID, selected, active]) {
            let normalized = pluginId.trimAscii()
            if (normalized.isEmpty() || seen.contains(normalized)) {
                continue
            }
            seen.add(normalized)
            out.add(memoryPluginSummaryRow(normalized, selected, active))
        }
        out
    }

    public static func activeMemoryPluginSummary(
        agentId!: String = "",
        purpose!: String = "default"
    ): JsonObject {
        let selected = selectedMemoryPluginId()
        let active = resolvedMemoryPluginId()
        let summary = memoryPluginSummaryRow(active, selected, active)
        summary.put("agentId", JsonString(agentId.trimAscii()))
        summary.put("purpose", JsonString(if (purpose.trimAscii().isEmpty()) { "default" } else { purpose.trimAscii() }))
        summary
    }

    public static func resolveBackendConfig(agentId!: String = "", purpose!: String = "default"): ResolvedMemoryBackendConfig {
        let resolvedAgentId = agentId.trimAscii()
        let resolvedPurpose = if (purpose.trimAscii().isEmpty()) { "default" } else { purpose.trimAscii() }
        if (!memoryPluginAvailable()) {
            return unavailableResolvedConfig(resolvedAgentId, resolvedPurpose)
        }
        match (configuredMemorySearchSelection(resolvedAgentId)) {
            case Some(selection) =>
                if (!selection.enabled) {
                    return disabledResolvedConfig(
                        resolvedAgentId,
                        resolvedPurpose,
                        selection.configScope
                    )
                }
                if (!selection.requestedBackend.isEmpty()) {
                    match (MemoryProviderRegistry.resolveMemoryBackendConfigSelection(selection.requestedBackend)) {
                        case Some(cfg) =>
                            let providerFields = memoryRuntimeEmbeddingProviderFields(cfg.providerId, resolvedAgentId)
                            return ResolvedMemoryBackendConfig(
                                cfg.providerId,
                                cfg.backend,
                                cfg.searchEnabled,
                                cfg.manualReindexSupported,
                                cfg.indexPath,
                                citations: CliConfig.memoryCitations.trimAscii(),
                                searchMode: resolvedSearchModeForBackend(cfg.backend),
                                agentId: resolvedAgentId,
                                purpose: resolvedPurpose,
                                configScope: selection.configScope,
                                memoryPluginId: activeMemoryPluginId(),
                                memoryPluginAvailable: true,
                                memoryPluginSlot: "memory",
                                model: resolvedMemorySearchModel(resolvedAgentId),
                                fallbackProviderId: resolvedMemorySearchFallbackProviderId(resolvedAgentId),
                                extraPaths: resolvedMemorySearchExtraPaths(resolvedAgentId),
                                qmdExtraCollections: resolvedMemorySearchQmdExtraCollections(resolvedAgentId),
                                remoteBaseUrl: resolvedMemorySearchRemoteBaseUrl(resolvedAgentId),
                                remoteApiKey: resolvedMemorySearchRemoteApiKey(resolvedAgentId),
                                remoteHeaders: resolvedMemorySearchRemoteHeaders(resolvedAgentId),
                                localConfig: resolvedMemorySearchLocalConfig(resolvedAgentId),
                                queryHybridConfig: resolvedMemorySearchQueryHybridConfig(resolvedAgentId),
                                storeConfig: resolvedMemorySearchStoreConfig(resolvedAgentId),
                                syncConfig: resolvedMemorySearchSyncConfig(resolvedAgentId),
                                outputDimensionality: resolvedMemorySearchOutputDimensionality(resolvedAgentId),
                                multimodalConfig: resolvedMemorySearchMultimodalConfig(resolvedAgentId),
                                embeddingProviderId: providerFields[0],
                                embeddingProviderTransport: providerFields[1],
                                embeddingProviderDefaultModel: providerFields[2],
                                embeddingProviderOwnerPluginId: providerFields[3],
                                embeddingProviderRegistered: providerFields[4],
                                embeddingProviderSupportsMultimodal: providerFields[5]
                            )
                        case None => ()
                    }
                }
            case None => ()
        }
        let agentRequested = configuredAgentRequestedBackend(resolvedAgentId)
        if (!agentRequested.isEmpty()) {
            match (MemoryProviderRegistry.resolveMemoryBackendConfigSelection(agentRequested)) {
                case Some(cfg) =>
                    let providerFields = memoryRuntimeEmbeddingProviderFields(cfg.providerId, resolvedAgentId)
                    return ResolvedMemoryBackendConfig(
                        cfg.providerId,
                        cfg.backend,
                        cfg.searchEnabled,
                        cfg.manualReindexSupported,
                        cfg.indexPath,
                        citations: CliConfig.memoryCitations.trimAscii(),
                        searchMode: resolvedSearchModeForBackend(cfg.backend),
                        agentId: resolvedAgentId,
                        purpose: resolvedPurpose,
                        configScope: "agent-manifest",
                        memoryPluginId: activeMemoryPluginId(),
                        memoryPluginAvailable: true,
                        memoryPluginSlot: "memory",
                        model: resolvedMemorySearchModel(resolvedAgentId),
                        fallbackProviderId: resolvedMemorySearchFallbackProviderId(resolvedAgentId),
                        extraPaths: resolvedMemorySearchExtraPaths(resolvedAgentId),
                        qmdExtraCollections: resolvedMemorySearchQmdExtraCollections(resolvedAgentId),
                        remoteBaseUrl: resolvedMemorySearchRemoteBaseUrl(resolvedAgentId),
                        remoteApiKey: resolvedMemorySearchRemoteApiKey(resolvedAgentId),
                        remoteHeaders: resolvedMemorySearchRemoteHeaders(resolvedAgentId),
                        localConfig: resolvedMemorySearchLocalConfig(resolvedAgentId),
                        queryHybridConfig: resolvedMemorySearchQueryHybridConfig(resolvedAgentId),
                        storeConfig: resolvedMemorySearchStoreConfig(resolvedAgentId),
                        syncConfig: resolvedMemorySearchSyncConfig(resolvedAgentId),
                        outputDimensionality: resolvedMemorySearchOutputDimensionality(resolvedAgentId),
                        multimodalConfig: resolvedMemorySearchMultimodalConfig(resolvedAgentId),
                        embeddingProviderId: providerFields[0],
                        embeddingProviderTransport: providerFields[1],
                        embeddingProviderDefaultModel: providerFields[2],
                        embeddingProviderOwnerPluginId: providerFields[3],
                        embeddingProviderRegistered: providerFields[4],
                        embeddingProviderSupportsMultimodal: providerFields[5]
                    )
                case None => ()
            }
        }
        let base = MemoryProviderRegistry.resolveMemoryBackendConfig()
        let providerFields = memoryRuntimeEmbeddingProviderFields(base.providerId, resolvedAgentId)
        ResolvedMemoryBackendConfig(
            base.providerId,
            base.backend,
            base.searchEnabled,
            base.manualReindexSupported,
            base.indexPath,
            citations: CliConfig.memoryCitations.trimAscii(),
            searchMode: resolvedSearchModeForBackend(base.backend),
            agentId: resolvedAgentId,
            purpose: resolvedPurpose,
            configScope: "global",
            memoryPluginId: activeMemoryPluginId(),
            memoryPluginAvailable: true,
            memoryPluginSlot: "memory",
            model: resolvedMemorySearchModel(resolvedAgentId),
            fallbackProviderId: resolvedMemorySearchFallbackProviderId(resolvedAgentId),
            extraPaths: resolvedMemorySearchExtraPaths(resolvedAgentId),
            qmdExtraCollections: resolvedMemorySearchQmdExtraCollections(resolvedAgentId),
            remoteBaseUrl: resolvedMemorySearchRemoteBaseUrl(resolvedAgentId),
            remoteApiKey: resolvedMemorySearchRemoteApiKey(resolvedAgentId),
            remoteHeaders: resolvedMemorySearchRemoteHeaders(resolvedAgentId),
            localConfig: resolvedMemorySearchLocalConfig(resolvedAgentId),
            queryHybridConfig: resolvedMemorySearchQueryHybridConfig(resolvedAgentId),
            storeConfig: resolvedMemorySearchStoreConfig(resolvedAgentId),
            syncConfig: resolvedMemorySearchSyncConfig(resolvedAgentId),
            outputDimensionality: resolvedMemorySearchOutputDimensionality(resolvedAgentId),
            multimodalConfig: resolvedMemorySearchMultimodalConfig(resolvedAgentId),
            embeddingProviderId: providerFields[0],
            embeddingProviderTransport: providerFields[1],
            embeddingProviderDefaultModel: providerFields[2],
            embeddingProviderOwnerPluginId: providerFields[3],
            embeddingProviderRegistered: providerFields[4],
            embeddingProviderSupportsMultimodal: providerFields[5]
        )
    }

    public static func previewResolvedBackendConfig(
        requestedBackend: String,
        agentId!: String = "",
        purpose!: String = "preview"
    ): Option<ResolvedMemoryBackendConfig> {
        match (MemoryProviderRegistry.resolveMemoryBackendConfigSelection(requestedBackend.trimAscii())) {
            case Some(cfg) =>
                Some(
                    resolvedConfigFromBackendConfig(
                        cfg,
                        agentId: agentId,
                        purpose: if (purpose.trimAscii().isEmpty()) { "preview" } else { purpose.trimAscii() },
                        configScope: "preview"
                    )
                )
            case None => None
        }
    }

    public static func activateBackend(providerId: String, startMaintenance!: Bool = true): Bool {
        let normalized = providerId.trimAscii()
        let ok = MemoryProviderRegistry.activate(normalized, startMaintenance: startMaintenance)
        if (ok && !normalized.isEmpty()) {
            CliConfig.memoryProvider = normalized
        }
        ok
    }

    public static func activeProviderName(): String {
        MemoryProviderRegistry.activeProviderName()
    }

    public static func registeredProviderIds(): Array<String> {
        MemoryProviderRegistry.registeredProviderIds()
    }

    public static func registeredBackendSummaries(): JsonArray {
        let out = JsonArray([])
        let requested = CliConfig.memoryProvider.trimAscii()
        let activeProviderId = activeProviderName().trimAscii()
        for (cfg in MemoryProviderRegistry.registeredBackendConfigs()) {
            let summary = resolvedConfigFromBackendConfig(cfg).toJsonObject()
            summary.put("active", (cfg.providerId.trimAscii() == activeProviderId).toJsonValue())
            summary.put("matchesRequested", backendMatchesRequested(cfg, requested).toJsonValue())
            out.add(summary)
        }
        out
    }

    public static func registeredBackendSelectionTargets(): JsonArray {
        let out = JsonArray([])
        let requested = CliConfig.memoryProvider.trimAscii()
        let activeProviderId = activeProviderName().trimAscii()
        for (cfg in MemoryProviderRegistry.registeredBackendConfigs()) {
            let resolved = resolvedConfigFromBackendConfig(cfg)
            let keys = resolved.selectionKeysJson()
            for (i in 0..keys.size()) {
                let keyValue = keys[i]
                let key = try {
                    keyValue.asString().getValue().trimAscii()
                } catch (_: Exception) {
                    ""
                }
                if (key.isEmpty()) {
                    continue
                }
                let row = resolved.toJsonObject()
                row.put("key", JsonString(key))
                row.put("selectionMode", JsonString(if (key == cfg.providerId.trimAscii()) { "provider-id" } else { "backend-id" }))
                row.put("active", (cfg.providerId.trimAscii() == activeProviderId).toJsonValue())
                row.put("matchesRequested", (key == requested).toJsonValue())
                out.add(row)
            }
        }
        out
    }

    public static func registeredBackendSelectionKeys(): Array<String> {
        let out = ArrayList<String>()
        let targets = registeredBackendSelectionTargets()
        for (i in 0..targets.size()) {
            let row = targets[i]
            let obj = row.asObject()
            let key = memoryRuntimeRegistryJsonString(obj, "key")
            if (key.isEmpty()) {
                continue
            }
            var exists = false
            for (current in out) {
                if (current == key) {
                    exists = true
                    break
                }
            }
            if (!exists) {
                out.add(key)
            }
        }
    out.toArray()
}

    public static func registeredOrchestrationBackendSummaries(): JsonArray {
        let out = JsonArray([])
        let activeId = MemoryProviderRegistry.currentOrchestrationBackendId().trimAscii()
        for (backendId in MemoryProviderRegistry.registeredOrchestrationBackendIds()) {
            let summary = JsonObject()
            summary.put("backendId", JsonString(backendId))
            summary.put("active", (backendId == activeId).toJsonValue())
            summary.put("capabilities", orchestrationCapabilitiesJson(backendId))
            out.add(summary)
        }
        out
    }

    public static func activeOrchestrationBackendSummary(
        agentId!: String = "",
        purpose!: String = "default"
    ): JsonObject {
        let resolved = resolveBackendConfig(agentId: agentId, purpose: purpose)
        let backendId = if (resolved.memoryPluginAvailable && resolved.searchEnabled && !resolved.providerId.trimAscii().isEmpty()) {
            MemoryProviderRegistry.currentOrchestrationBackendId().trimAscii()
        } else {
            ""
        }
        let summary = JsonObject()
        summary.put("backendId", JsonString(backendId))
        summary.put("active", (resolved.memoryPluginAvailable && resolved.searchEnabled && !resolved.providerId.trimAscii().isEmpty()).toJsonValue())
        summary.put("agentId", JsonString(resolved.agentId))
        summary.put("purpose", JsonString(resolved.purpose))
        summary.put("configScope", JsonString(resolved.configScope))
        summary.put("memoryPluginId", JsonString(resolved.memoryPluginId))
        summary.put("memoryPluginAvailable", resolved.memoryPluginAvailable.toJsonValue())
        summary.put("capabilities", orchestrationCapabilitiesJson(backendId))
        summary
    }

    public static func activeSearchBackendSummary(
        agentId!: String = "",
        purpose!: String = "default"
    ): JsonObject {
        let resolved = resolveBackendConfig(agentId: agentId, purpose: purpose)
        let summary = resolved.toJsonObject()
        summary.put("active", (resolved.memoryPluginAvailable && resolved.searchEnabled && !resolved.providerId.trimAscii().isEmpty()).toJsonValue())
        summary.put("memoryPluginAvailable", resolved.memoryPluginAvailable.toJsonValue())
        summary.put("memoryPluginId", JsonString(resolved.memoryPluginId))
        summary
    }

    public static func backendSelectionSummary(
        agentId!: String = "",
        purpose!: String = "default"
    ): JsonObject {
        let resolved = resolveBackendConfig(agentId: agentId, purpose: purpose)
        let requested = configuredRequestedBackend(agentId.trimAscii())
        let out = JsonObject()
        out.put("requestedBackend", JsonString(requested))
        out.put("selectedProviderId", JsonString(resolved.providerId))
        out.put("selectedBackend", JsonString(resolved.backend))
        out.put("selectionMode", JsonString(if (!resolved.memoryPluginAvailable) { "memory-plugin-disabled" } else if (!resolved.searchEnabled && resolved.providerId.trimAscii().isEmpty()) { "memory-search-disabled" } else { selectionModeForResolved(requested, resolved) }))
        out.put("configScope", JsonString(resolved.configScope))
        out.put("agentId", JsonString(resolved.agentId))
        out.put("purpose", JsonString(resolved.purpose))
        out.put("memoryPluginId", JsonString(resolved.memoryPluginId))
        out.put("memoryPluginAvailable", resolved.memoryPluginAvailable.toJsonValue())
        out
    }

    public static func agentScopedResolveSummary(
        agentId!: String = "",
        purpose!: String = "default"
    ): JsonObject {
        let resolved = resolveBackendConfig(agentId: agentId, purpose: purpose)
        let normalizedAgentId = resolved.agentId
        let out = JsonObject()
        out.put("agentId", JsonString(normalizedAgentId))
        out.put("purpose", JsonString(resolved.purpose))
        out.put("configScope", JsonString(resolved.configScope))
        out.put("inheritsGlobal", (resolved.configScope == "global").toJsonValue())
        out.put("scopeSource", JsonString(if (!resolved.memoryPluginAvailable) { "plugins.slots.memory" } else if (resolved.configScope == "global") { "memory.backend" } else { resolved.configScope }))
        out.put("requestedBackend", JsonString(configuredRequestedBackend(normalizedAgentId)))
        out.put("resolvedBackend", JsonString(resolved.backend))
        out.put("resolvedProviderId", JsonString(resolved.providerId))
        out.put("memoryPluginId", JsonString(resolved.memoryPluginId))
        out.put("memoryPluginAvailable", resolved.memoryPluginAvailable.toJsonValue())
        out.put("resolvedBackendConfig", resolved.toJsonObject())
        out
    }

    public static func previewAgentScopedResolveSummary(
        requestedBackend: String,
        agentId!: String = "",
        purpose!: String = "agent-override-preview"
    ): JsonObject {
        let normalizedRequested = requestedBackend.trimAscii()
        let fallback = resolveBackendConfig(agentId: agentId, purpose: purpose)
        let out = JsonObject()
        out.put("requestedBackend", JsonString(normalizedRequested))
        out.put("agentId", JsonString(fallback.agentId))
        out.put("purpose", JsonString(fallback.purpose))
        out.put("memoryPluginId", JsonString(fallback.memoryPluginId))
        out.put("memoryPluginAvailable", fallback.memoryPluginAvailable.toJsonValue())
        match (previewResolvedBackendConfig(normalizedRequested, agentId: agentId, purpose: purpose)) {
            case Some(resolved) =>
                out.put("matched", true.toJsonValue())
                out.put("configScope", JsonString("agent-override-preview"))
                out.put("inheritsGlobal", false.toJsonValue())
                out.put("scopeSource", JsonString("agent.memory.backend"))
                out.put("selectedProviderId", JsonString(resolved.providerId))
                out.put("selectedBackend", JsonString(resolved.backend))
                out.put("selectionMode", JsonString(selectionModeForResolved(normalizedRequested, resolved)))
                out.put("resolvedBackendConfig", resolved.toJsonObject())
            case None =>
                out.put("matched", false.toJsonValue())
                out.put("configScope", JsonString(fallback.configScope))
                out.put("inheritsGlobal", (fallback.configScope == "global").toJsonValue())
                out.put("scopeSource", JsonString(if (!fallback.memoryPluginAvailable) { "plugins.slots.memory" } else { "memory.backend" }))
                out.put("selectedProviderId", JsonString(fallback.providerId))
                out.put("selectedBackend", JsonString(fallback.backend))
                out.put("selectionMode", JsonString(if (!fallback.memoryPluginAvailable) { "memory-plugin-disabled" } else { selectionModeForResolved(normalizedRequested, fallback) }))
                out.put("resolvedBackendConfig", fallback.toJsonObject())
        }
        out
    }

    public static func previewBackendSelectionSummary(
        requestedBackend: String,
        agentId!: String = "",
        purpose!: String = "preview"
    ): JsonObject {
        let requested = requestedBackend.trimAscii()
        let out = JsonObject()
        out.put("requestedBackend", JsonString(requested))
        out.put("memoryPluginId", JsonString(activeMemoryPluginId()))
        out.put("memoryPluginAvailable", memoryPluginAvailable().toJsonValue())
        match (previewResolvedBackendConfig(requested, agentId: agentId, purpose: purpose)) {
            case Some(resolved) =>
                out.put("matched", true.toJsonValue())
                out.put("selectedProviderId", JsonString(resolved.providerId))
                out.put("selectedBackend", JsonString(resolved.backend))
                out.put("selectionMode", JsonString(selectionModeForResolved(requested, resolved)))
                out.put("configScope", JsonString(resolved.configScope))
                out.put("agentId", JsonString(resolved.agentId))
                out.put("purpose", JsonString(resolved.purpose))
                out.put("resolvedBackendConfig", resolved.toJsonObject())
            case None =>
                out.put("matched", false.toJsonValue())
                out.put("selectedProviderId", JsonString(""))
                out.put("selectedBackend", JsonString(""))
                out.put("selectionMode", JsonString(""))
                out.put("configScope", JsonString(if (!memoryPluginAvailable()) { "plugins.slots.memory" } else { "global" }))
                out.put("agentId", JsonString(agentId.trimAscii()))
                out.put("purpose", JsonString(if (purpose.trimAscii().isEmpty()) { "preview" } else { purpose.trimAscii() }))
        }
        out
    }

    public static func activeSearchBackend(): MemoryProvider {
        activeSearchBackend(agentId: "", purpose: "default")
    }

    public static func activeSearchBackend(agentId!: String, purpose!: String): MemoryProvider {
        let resolved = resolveBackendConfig(agentId: agentId, purpose: purpose)
        if (resolved.configScope == "global") {
            return MemoryProviderRegistry.currentSearchBackend()
        }
        match (MemoryProviderRegistry.resolveSearchBackendSelection(resolved.providerId)) {
            case Some(provider) => provider
            case None => MemoryProviderRegistry.currentSearchBackend()
        }
    }

    public static func activeOrchestrationBackend(): MemoryOrchestrationBackend {
        activeOrchestrationBackend(agentId: "", purpose: "default")
    }

    public static func activeOrchestrationBackend(
        agentId!: String,
        purpose!: String
    ): MemoryOrchestrationBackend {
        let _resolved = resolveBackendConfig(agentId: agentId, purpose: purpose)
        MemoryProviderRegistry.currentOrchestrationBackend()
    }

    public static func resolveActiveBackendConfig(): MemoryBackendConfig {
        resolveBackendConfig().toBackendConfig()
    }

    public static func getActiveSearchManager(agentId!: String = "", purpose!: String = "default"): MemorySearchManagerResult {
        if (!memoryPluginAvailable()) {
            return MemorySearchManagerResult(error: memoryPluginUnavailableError())
        }
        let resolved = resolveBackendConfig(agentId: agentId, purpose: purpose)
        if (!resolved.searchEnabled || resolved.providerId.trimAscii().isEmpty()) {
            return MemorySearchManagerResult(error: "memory search disabled")
        }
        if (resolved.configScope == "global") {
            return MemoryProviderRegistry.getMemorySearchManager()
        }
        MemoryProviderRegistry.getMemorySearchManagerForSelection(resolved.providerId)
    }

    public static func armActiveSearchManager(agentId!: String = "", purpose!: String = "startup"): MemorySearchManagerResult {
        if (!memoryPluginAvailable()) {
            return MemorySearchManagerResult(error: memoryPluginUnavailableError())
        }
        let resolved = resolveBackendConfig(agentId: agentId, purpose: purpose)
        if (!resolved.searchEnabled || resolved.providerId.trimAscii().isEmpty()) {
            return MemorySearchManagerResult(error: "memory search disabled")
        }
        if (resolved.configScope == "global") {
            return MemoryProviderRegistry.armActiveSearchManager()
        }
        MemoryProviderRegistry.getMemorySearchManagerForSelection(resolved.providerId)
    }

    public static func startActiveMaintenance(): Unit {
        if (!memoryPluginAvailable()) {
            return
        }
        MemoryProviderRegistry.startActiveMaintenance()
    }

    public static func stopActiveMaintenance(): Unit {
        if (!memoryPluginAvailable()) {
            return
        }
        MemoryProviderRegistry.stopActiveMaintenance()
    }

    public static func closeActiveSearchManagers(): Unit {
        if (!memoryPluginAvailable()) {
            return
        }
        MemoryProviderRegistry.closeAllMemorySearchManagers()
    }
}
