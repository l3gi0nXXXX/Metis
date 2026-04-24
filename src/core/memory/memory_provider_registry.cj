package metis.core.memory

import metis.core.config.{CliConfig, CliSettingManager}
import metis.utils.ShellUtils

import magic.jsonable.*
import magic.log.LogUtils

import std.collection.{ArrayList, HashMap}
import std.convert.*
import std.fs.{Path, File, Directory, FileInfo, exists, remove}
import std.sort.sort
import std.sync.Mutex
import std.time.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private func memoryProviderMultimodalEnabled(multimodalConfig: JsonObject): Bool {
    match (multimodalConfig.get("enabled")) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_: Exception) { false }
        case None => false
    }
}

public class MemoryBackendConfig {
    public let providerId: String
    public let backend: String
    public let searchEnabled: Bool
    public let manualReindexSupported: Bool
    public let indexPath: String

    public init(
        providerId: String,
        backend: String,
        searchEnabled: Bool,
        manualReindexSupported: Bool,
        indexPath: String
    ) {
        this.providerId = providerId
        this.backend = backend
        this.searchEnabled = searchEnabled
        this.manualReindexSupported = manualReindexSupported
        this.indexPath = indexPath
    }
}

public class ResolvedMemoryBackendConfig {
    public let providerId: String
    public let backend: String
    public let searchEnabled: Bool
    public let manualReindexSupported: Bool
    public let indexPath: String
    public let citations: String
    public let searchMode: String
    public let agentId: String
    public let purpose: String
    public let configScope: String
    public let memoryPluginId: String
    public let memoryPluginAvailable: Bool
    public let memoryPluginSlot: String
    public let model: String
    public let fallbackProviderId: String
    public let extraPaths: Array<String>
    public let qmdExtraCollections: Array<String>
    public let remoteBaseUrl: String
    public let remoteApiKey: String
    public let remoteHeaders: JsonObject
    public let localConfig: JsonObject
    public let queryHybridConfig: JsonObject
    public let storeConfig: JsonObject
    public let syncConfig: JsonObject
    public let outputDimensionality: Int64
    public let multimodalConfig: JsonObject
    public let embeddingProviderId: String
    public let embeddingProviderTransport: String
    public let embeddingProviderDefaultModel: String
    public let embeddingProviderOwnerPluginId: String
    public let embeddingProviderRegistered: Bool
    public let embeddingProviderSupportsMultimodal: Bool
    public let embeddingProviderAllowExplicitWhenConfiguredAuto: Bool

    public init(
        providerId: String,
        backend: String,
        searchEnabled: Bool,
        manualReindexSupported: Bool,
        indexPath: String,
        citations!: String = "auto",
        searchMode!: String = "",
        agentId!: String = "",
        purpose!: String = "default",
        configScope!: String = "global",
        memoryPluginId!: String = "memory-core",
        memoryPluginAvailable!: Bool = true,
        memoryPluginSlot!: String = "memory",
        model!: String = "",
        fallbackProviderId!: String = "none",
        extraPaths!: Array<String> = Array<String>(),
        qmdExtraCollections!: Array<String> = Array<String>(),
        remoteBaseUrl!: String = "",
        remoteApiKey!: String = "",
        remoteHeaders!: JsonObject = JsonObject(),
        localConfig!: JsonObject = JsonObject(),
        queryHybridConfig!: JsonObject = JsonObject(),
        storeConfig!: JsonObject = JsonObject(),
        syncConfig!: JsonObject = JsonObject(),
        outputDimensionality!: Int64 = 0,
        multimodalConfig!: JsonObject = JsonObject(),
        embeddingProviderId!: String = "",
        embeddingProviderTransport!: String = "",
        embeddingProviderDefaultModel!: String = "",
        embeddingProviderOwnerPluginId!: String = "",
        embeddingProviderRegistered!: Bool = false,
        embeddingProviderSupportsMultimodal!: Bool = false,
        embeddingProviderAllowExplicitWhenConfiguredAuto!: Bool = false
    ) {
        this.providerId = providerId
        this.backend = backend
        this.searchEnabled = searchEnabled
        this.manualReindexSupported = manualReindexSupported
        this.indexPath = indexPath
        this.citations = citations
        this.searchMode = searchMode
        this.agentId = agentId
        this.purpose = purpose
        this.configScope = configScope
        this.memoryPluginId = memoryPluginId
        this.memoryPluginAvailable = memoryPluginAvailable
        this.memoryPluginSlot = memoryPluginSlot
        this.model = model
        this.fallbackProviderId = fallbackProviderId
        this.extraPaths = extraPaths
        this.qmdExtraCollections = qmdExtraCollections
        this.remoteBaseUrl = remoteBaseUrl
        this.remoteApiKey = remoteApiKey
        this.remoteHeaders = remoteHeaders
        this.localConfig = localConfig
        this.queryHybridConfig = queryHybridConfig
        this.storeConfig = storeConfig
        this.syncConfig = syncConfig
        this.outputDimensionality = outputDimensionality
        this.multimodalConfig = multimodalConfig
        this.embeddingProviderId = embeddingProviderId
        this.embeddingProviderTransport = embeddingProviderTransport
        this.embeddingProviderDefaultModel = embeddingProviderDefaultModel
        this.embeddingProviderOwnerPluginId = embeddingProviderOwnerPluginId
        this.embeddingProviderRegistered = embeddingProviderRegistered
        this.embeddingProviderSupportsMultimodal = embeddingProviderSupportsMultimodal
        this.embeddingProviderAllowExplicitWhenConfiguredAuto = embeddingProviderAllowExplicitWhenConfiguredAuto
    }

    public func toBackendConfig(): MemoryBackendConfig {
        MemoryBackendConfig(
            providerId,
            backend,
            searchEnabled,
            manualReindexSupported,
            indexPath
        )
    }

    public func capabilitiesJson(): JsonObject {
        let out = JsonObject()
        let created = embeddingProviderCreateResult()
        out.put("providerId", JsonString(providerId))
        out.put("backend", JsonString(backend))
        out.put("memoryPluginId", JsonString(memoryPluginId))
        out.put("memoryPluginAvailable", memoryPluginAvailable.toJsonValue())
        out.put("memoryPluginSlot", JsonString(memoryPluginSlot))
        out.put("searchEnabled", searchEnabled.toJsonValue())
        out.put("manualReindexSupported", manualReindexSupported.toJsonValue())
        out.put("citations", JsonString(citations))
        if (!searchMode.trimAscii().isEmpty()) {
            out.put("searchMode", JsonString(searchMode))
        }
        out.put("supportsStatus", true.toJsonValue())
        out.put("supportsFixArtifacts", true.toJsonValue())
        out.put("supportsIndexSnapshot", true.toJsonValue())
        out.put("supportsOrchestration", (providerId == "local" || providerId == "compat-local").toJsonValue())
        out.put("supportsBackgroundMaintenance", (backend == "qmd").toJsonValue())
        out.put("supportsSessionExport", (backend == "qmd" && CliConfig.qmdSessionsEnabled).toJsonValue())
        out.put("supportsScopePolicy", (backend == "qmd").toJsonValue())
        out.put("supportsMcporter", (backend == "qmd" && CliConfig.qmdMcporterEnabled).toJsonValue())
        out.put("supportsPathCollections", (backend == "qmd").toJsonValue())
        out.put("supportsExternalCommand", (backend == "external-command").toJsonValue())
        out.put("supportsLocalFileFallback", (backend.contains("local-file")).toJsonValue())
        out.put("hasEmbeddingProviderAdapter", embeddingProviderRegistered.toJsonValue())
        out.put("hasEmbeddingProviderRuntime", created.runtime.isSome().toJsonValue())
        if (!embeddingProviderTransport.trimAscii().isEmpty()) {
            out.put("embeddingProviderTransport", JsonString(embeddingProviderTransport))
        }
        out.put("embeddingProviderSupportsMultimodal", embeddingProviderSupportsMultimodal.toJsonValue())
        out.put(
            "embeddingProviderAllowExplicitWhenConfiguredAuto",
            embeddingProviderAllowExplicitWhenConfiguredAuto.toJsonValue()
        )
        match (created.runtime) {
            case Some(runtime) =>
                out.put("embeddingProviderBatchEmbedSupported", runtime.batchEmbedSupported.toJsonValue())
            case None => ()
        }
        out
    }

    public func backendConfigJson(): JsonObject {
        let out = JsonObject()
        out.put("indexPath", JsonString(indexPath))
        if (backend == "qmd") {
            let qmd = JsonObject()
            qmd.put("command", JsonString(CliConfig.qmdCommand.trimAscii()))
            qmd.put("searchMode", JsonString(searchMode))
            let paths = JsonArray([])
            for (path in CliConfig.qmdPaths) {
                let trimmed = path.trimAscii()
                if (!trimmed.isEmpty()) {
                    paths.add(JsonString(trimmed))
                }
            }
            qmd.put("paths", paths)
            let sessions = JsonObject()
            sessions.put("enabled", CliConfig.qmdSessionsEnabled.toJsonValue())
            sessions.put("exportDir", JsonString(CliConfig.qmdSessionsExportDir.trimAscii()))
            sessions.put("retentionDays", CliConfig.qmdSessionsRetentionDays.toJsonValue())
            qmd.put("sessions", sessions)
            let update = JsonObject()
            update.put("onBoot", CliConfig.qmdUpdateOnBoot.toJsonValue())
            update.put("waitForBootSync", CliConfig.qmdUpdateWaitForBootSync.toJsonValue())
            update.put("intervalMs", CliConfig.qmdUpdateIntervalMs.toJsonValue())
            update.put("debounceMs", CliConfig.qmdUpdateDebounceMs.toJsonValue())
            update.put("embedIntervalMs", CliConfig.qmdUpdateEmbedIntervalMs.toJsonValue())
            update.put("commandTimeoutMs", CliConfig.qmdUpdateCommandTimeoutMs.toJsonValue())
            update.put("updateTimeoutMs", CliConfig.qmdUpdateUpdateTimeoutMs.toJsonValue())
            update.put("embedTimeoutMs", CliConfig.qmdUpdateEmbedTimeoutMs.toJsonValue())
            qmd.put("update", update)
            let limits = JsonObject()
            limits.put("maxResults", CliConfig.qmdLimitsMaxResults.toJsonValue())
            limits.put("maxSnippetChars", CliConfig.qmdLimitsMaxSnippetChars.toJsonValue())
            limits.put("maxInjectedChars", CliConfig.qmdLimitsMaxInjectedChars.toJsonValue())
            limits.put("timeoutMs", CliConfig.qmdLimitsTimeoutMs.toJsonValue())
            qmd.put("limits", limits)
            let scope = JsonObject()
            scope.put("default", JsonString(CliConfig.qmdScopeDefault.trimAscii()))
            scope.put("ruleCount", CliConfig.qmdScopeRuleActions.size.toJsonValue())
            qmd.put("scope", scope)
            let mcporter = JsonObject()
            mcporter.put("enabled", CliConfig.qmdMcporterEnabled.toJsonValue())
            mcporter.put("serverName", JsonString(CliConfig.qmdMcporterServerName.trimAscii()))
            mcporter.put("startDaemon", CliConfig.qmdMcporterStartDaemon.toJsonValue())
            qmd.put("mcporter", mcporter)
            out.put("qmd", qmd)
        }
        out
    }

    public func selectionKeysJson(): JsonArray {
        let out = ArrayList<JsonValue>()
        let normalizedProviderId = providerId.trimAscii()
        let normalizedBackend = backend.trimAscii()
        if (!normalizedProviderId.isEmpty()) {
            out.add(JsonString(normalizedProviderId))
        }
        if (!normalizedBackend.isEmpty() && normalizedBackend != normalizedProviderId) {
            out.add(JsonString(normalizedBackend))
        }
        JsonArray(out.toArray())
    }

    public func configTemplateJson(): JsonObject {
        let out = JsonObject()
        let memory = JsonObject()
        memory.put("backend", JsonString(providerId))
        memory.put("citations", JsonString(citations))
        if (backend == "qmd") {
            let qmd = JsonObject()
            qmd.put("command", JsonString(CliConfig.qmdCommand.trimAscii()))
            qmd.put("searchMode", JsonString(if (searchMode.trimAscii().isEmpty()) { "search" } else { searchMode.trimAscii() }))
            qmd.put("includeDefaultMemory", CliConfig.qmdIncludeDefaultMemory.toJsonValue())
            let sessions = JsonObject()
            sessions.put("enabled", CliConfig.qmdSessionsEnabled.toJsonValue())
            sessions.put("exportDir", JsonString(CliConfig.qmdSessionsExportDir.trimAscii()))
            sessions.put("retentionDays", CliConfig.qmdSessionsRetentionDays.toJsonValue())
            qmd.put("sessions", sessions)
            let update = JsonObject()
            update.put("onBoot", CliConfig.qmdUpdateOnBoot.toJsonValue())
            update.put("waitForBootSync", CliConfig.qmdUpdateWaitForBootSync.toJsonValue())
            qmd.put("update", update)
            memory.put("qmd", qmd)
        } else if (backend == "external-command") {
            memory.put("externalCommand", JsonString(CliConfig.externalMemoryCommand.trimAscii()))
        }
        out.put("memory", memory)
        out
    }

    public func registrationMetadataJson(): JsonObject {
        let out = JsonObject()
        let created = embeddingProviderCreateResult()
        let normalizedBackend = backend.trimAscii()
        out.put("providerId", JsonString(providerId))
        out.put("backend", JsonString(normalizedBackend))
        out.put("defaultPreferred", (providerId == "local").toJsonValue())
        out.put("requiresCommandConfig", (normalizedBackend == "qmd" || normalizedBackend == "external-command").toJsonValue())
        out.put("requiresPathConfig", (normalizedBackend == "qmd").toJsonValue())
        out.put("requiresSessionsConfig", (normalizedBackend == "qmd").toJsonValue())
        out.put("supportsPreviewSelection", true.toJsonValue())
        out.put("activationMode", JsonString("runtime-registry"))
        out.put("configKey", JsonString("memory.backend"))
        out.put("pluginSlot", JsonString(memoryPluginSlot))
        out.put("pluginSlotKey", JsonString("plugins.slots.memory"))
        out.put("pluginOwner", JsonString(memoryPluginId))
        out.put("pluginAvailable", memoryPluginAvailable.toJsonValue())
        out.put("memoryEmbeddingProviderRegistered", embeddingProviderRegistered.toJsonValue())
        if (!embeddingProviderId.trimAscii().isEmpty()) {
            out.put("memoryEmbeddingProviderId", JsonString(embeddingProviderId))
        }
        if (!embeddingProviderTransport.trimAscii().isEmpty()) {
            out.put("memoryEmbeddingProviderTransport", JsonString(embeddingProviderTransport))
        }
        if (!embeddingProviderDefaultModel.trimAscii().isEmpty()) {
            out.put("memoryEmbeddingProviderDefaultModel", JsonString(embeddingProviderDefaultModel))
        }
        if (!embeddingProviderOwnerPluginId.trimAscii().isEmpty()) {
            out.put("memoryEmbeddingProviderOwnerPluginId", JsonString(embeddingProviderOwnerPluginId))
        }
        out.put("memoryEmbeddingProviderSupportsMultimodal", embeddingProviderSupportsMultimodal.toJsonValue())
        out.put(
            "memoryEmbeddingProviderAllowExplicitWhenConfiguredAuto",
            embeddingProviderAllowExplicitWhenConfiguredAuto.toJsonValue()
        )
        out.put("memoryEmbeddingProviderContinueAutoSelection", created.continueAutoSelection.toJsonValue())
        match (created.runtime) {
            case Some(runtime) =>
                out.put("memoryEmbeddingProviderBatchEmbedSupported", runtime.batchEmbedSupported.toJsonValue())
            case None => ()
        }
        if (!created.error.trimAscii().isEmpty()) {
            out.put("memoryEmbeddingProviderCreateError", JsonString(created.error.trimAscii()))
        }
        if (!model.trimAscii().isEmpty()) {
            out.put("memorySearchModel", JsonString(model))
        }
        if (outputDimensionality > 0) {
            out.put("memorySearchOutputDimensionality", outputDimensionality.toJsonValue())
        }
        out.put("memorySearchFallback", JsonString(fallbackProviderId))
        out.put("memorySearchExtraPathCount", extraPaths.size.toJsonValue())
        out.put("memorySearchQmdExtraCollectionCount", qmdExtraCollections.size.toJsonValue())
        out.put(
            "memorySearchRemoteConfigured",
            ((!remoteBaseUrl.trimAscii().isEmpty()) || (!remoteApiKey.trimAscii().isEmpty()) || (remoteHeaders.toJsonString() != "{}")).toJsonValue()
        )
        out
    }

    public func configValidationJson(): JsonObject {
        let out = JsonObject()
        let normalizedBackend = backend.trimAscii()
        let issues = ArrayList<JsonValue>()
        var valid = true

        if (normalizedBackend == "qmd") {
            if (CliConfig.qmdCommand.trimAscii().isEmpty()) {
                valid = false
                issues.add(JsonString("qmd.command is empty"))
            }
            if (searchMode.trimAscii().isEmpty()) {
                valid = false
                issues.add(JsonString("qmd.searchMode is empty"))
            }
        } else if (normalizedBackend == "external-command") {
            if (CliConfig.externalMemoryCommand.trimAscii().isEmpty()) {
                valid = false
                issues.add(JsonString("externalMemoryCommand is empty"))
            }
        }
        if (memoryProviderMultimodalEnabled(multimodalConfig)) {
            if (embeddingProviderId.trimAscii().isEmpty()) {
                valid = false
                issues.add(JsonString("agents.*.memorySearch.multimodal requires a resolved embedding provider adapter"))
            } else if (!embeddingProviderSupportsMultimodal) {
                valid = false
                issues.add(
                    JsonString(
                        "agents.*.memorySearch.multimodal requires a provider adapter that supports multimodal embeddings for the configured model."
                    )
                )
            }
            if (fallbackProviderId.trimAscii() != "none") {
                valid = false
                issues.add(
                    JsonString(
                        "agents.*.memorySearch.multimodal does not support memorySearch.fallback. Set fallback to \"none\"."
                    )
                )
            }
        }

        out.put("valid", valid.toJsonValue())
        out.put("issueCount", issues.size.toJsonValue())
        out.put("issues", JsonArray(issues.toArray()))
        out
    }

    private func embeddingProviderCreateResult(): MemoryEmbeddingProviderCreateResult {
        let requestedProviderId = if (!embeddingProviderId.trimAscii().isEmpty()) {
            embeddingProviderId.trimAscii()
        } else {
            providerId.trimAscii()
        }
        createMemoryEmbeddingProviderRuntime(
            requestedProviderId,
            model: model.trimAscii(),
            outputDimensionality: outputDimensionality,
            agentId: agentId.trimAscii()
        )
    }

    public func configSchemaJson(): JsonObject {
        let out = JsonObject()
        let normalizedBackend = backend.trimAscii()
        let required = ArrayList<JsonValue>()
        let optional = ArrayList<JsonValue>()

        required.add(JsonString("memory.backend"))
        optional.add(JsonString("memory.citations"))

        if (normalizedBackend == "qmd") {
            required.add(JsonString("memory.qmd.command"))
            required.add(JsonString("memory.qmd.searchMode"))
            optional.add(JsonString("memory.qmd.includeDefaultMemory"))
            optional.add(JsonString("memory.qmd.paths"))
            optional.add(JsonString("memory.qmd.sessions"))
            optional.add(JsonString("memory.qmd.update"))
            optional.add(JsonString("memory.qmd.limits"))
            optional.add(JsonString("memory.qmd.scope"))
            optional.add(JsonString("memory.qmd.mcporter"))
        } else if (normalizedBackend == "external-command") {
            required.add(JsonString("externalMemoryCommand"))
            optional.add(JsonString("externalMemoryArgs"))
            optional.add(JsonString("externalMemoryTimeoutMs"))
            optional.add(JsonString("externalMemoryBackendLabel"))
            optional.add(JsonString("externalMemoryIndexPathHint"))
        }

        out.put("requiredKeys", JsonArray(required.toArray()))
        out.put("optionalKeys", JsonArray(optional.toArray()))
        out.put("configRoot", JsonString("memory"))
        out
    }

    public func embeddingProviderCreateResultJson(): JsonObject {
        embeddingProviderCreateResult().toJsonObject()
    }

    public func embeddingProviderRuntimeJson(): JsonObject {
        match (embeddingProviderCreateResult().runtime) {
            case Some(runtime) => runtime.toJsonObject()
            case None => JsonObject()
        }
    }

    public func embeddingProviderCreateDiagnosticsJson(): JsonObject {
        let out = JsonObject()
        let created = embeddingProviderCreateResult()
        out.put("continueAutoSelection", created.continueAutoSelection.toJsonValue())
        if (!created.error.trimAscii().isEmpty()) {
            out.put("error", JsonString(created.error.trimAscii()))
        }
        out
    }

    public func toJsonObject(): JsonObject {
        let out = JsonObject()
        out.put("providerId", JsonString(providerId))
        out.put("backend", JsonString(backend))
        out.put("indexPath", JsonString(indexPath))
        out.put("citations", JsonString(citations))
        out.put("searchEnabled", searchEnabled.toJsonValue())
        out.put("manualReindexSupported", manualReindexSupported.toJsonValue())
        out.put("agentId", JsonString(agentId))
        out.put("purpose", JsonString(purpose))
        out.put("configScope", JsonString(configScope))
        out.put("memoryPluginId", JsonString(memoryPluginId))
        out.put("memoryPluginAvailable", memoryPluginAvailable.toJsonValue())
        out.put("memoryPluginSlot", JsonString(memoryPluginSlot))
        if (!model.trimAscii().isEmpty()) {
            out.put("model", JsonString(model))
        }
        out.put("fallbackProviderId", JsonString(fallbackProviderId))
        let extraPathsJson = JsonArray([])
        for (path in extraPaths) {
            extraPathsJson.add(JsonString(path))
        }
        out.put("extraPaths", extraPathsJson)
        let qmdExtraCollectionsJson = JsonArray([])
        for (collection in qmdExtraCollections) {
            qmdExtraCollectionsJson.add(JsonString(collection))
        }
        out.put("qmdExtraCollections", qmdExtraCollectionsJson)
        let remote = JsonObject()
        if (!remoteBaseUrl.trimAscii().isEmpty()) {
            remote.put("baseUrl", JsonString(remoteBaseUrl))
        }
        if (!remoteApiKey.trimAscii().isEmpty()) {
            remote.put("apiKey", JsonString(remoteApiKey))
        }
        if (remoteHeaders.toJsonString() != "{}") {
            remote.put("headers", remoteHeaders)
        }
        if (remote.toJsonString() != "{}") {
            out.put("remote", remote)
        }
        if (localConfig.toJsonString() != "{}") {
            out.put("local", localConfig)
        }
        if (outputDimensionality > 0) {
            out.put("outputDimensionality", outputDimensionality.toJsonValue())
        }
        if (multimodalConfig.toJsonString() != "{}") {
            out.put("multimodal", multimodalConfig)
        }
        if (queryHybridConfig.toJsonString() != "{}") {
            let query = JsonObject()
            query.put("hybrid", queryHybridConfig)
            out.put("query", query)
        }
        if (storeConfig.toJsonString() != "{}") {
            out.put("store", storeConfig)
        }
        if (syncConfig.toJsonString() != "{}") {
            out.put("sync", syncConfig)
        }
        let embeddingProvider = JsonObject()
        let created = embeddingProviderCreateResult()
        if (!embeddingProviderId.trimAscii().isEmpty()) {
            embeddingProvider.put("id", JsonString(embeddingProviderId))
        }
        if (!embeddingProviderTransport.trimAscii().isEmpty()) {
            embeddingProvider.put("transport", JsonString(embeddingProviderTransport))
        }
        if (!embeddingProviderDefaultModel.trimAscii().isEmpty()) {
            embeddingProvider.put("defaultModel", JsonString(embeddingProviderDefaultModel))
        }
        if (!embeddingProviderOwnerPluginId.trimAscii().isEmpty()) {
            embeddingProvider.put("ownerPluginId", JsonString(embeddingProviderOwnerPluginId))
        }
        embeddingProvider.put("registered", embeddingProviderRegistered.toJsonValue())
        embeddingProvider.put("supportsMultimodalEmbeddings", embeddingProviderSupportsMultimodal.toJsonValue())
        embeddingProvider.put(
            "allowExplicitWhenConfiguredAuto",
            embeddingProviderAllowExplicitWhenConfiguredAuto.toJsonValue()
        )
        match (created.provider) {
            case Some(provider) =>
                if (provider.maxInputTokens > 0) {
                    embeddingProvider.put("maxInputTokens", provider.maxInputTokens.toJsonValue())
                }
                if (provider.outputDimensionality > 0) {
                    embeddingProvider.put("outputDimensionality", provider.outputDimensionality.toJsonValue())
                }
            case None => ()
        }
        match (created.runtime) {
            case Some(runtime) =>
                embeddingProvider.put("batchEmbedSupported", runtime.batchEmbedSupported.toJsonValue())
            case None => ()
        }
        if (embeddingProvider.toJsonString() != "{}") {
            out.put("embeddingProvider", embeddingProvider)
        }
        let embeddingProviderCreate = created.toJsonObject()
        if (embeddingProviderCreate.toJsonString() != "{}") {
            out.put("embeddingProviderCreate", embeddingProviderCreate)
        }
        let embeddingProviderRuntime = embeddingProviderRuntimeJson()
        if (embeddingProviderRuntime.toJsonString() != "{}") {
            out.put("embeddingProviderRuntime", embeddingProviderRuntime)
        }
        let embeddingProviderDiagnostics = embeddingProviderCreateDiagnosticsJson()
        if (embeddingProviderDiagnostics.toJsonString() != "{}") {
            out.put("embeddingProviderDiagnostics", embeddingProviderDiagnostics)
        }
        if (!searchMode.trimAscii().isEmpty()) {
            out.put("searchMode", JsonString(searchMode))
        }
        out.put("capabilities", capabilitiesJson())
        out.put("backendConfig", backendConfigJson())
        out.put("selectionKeys", selectionKeysJson())
        out.put("configTemplate", configTemplateJson())
        out.put("registrationMetadata", registrationMetadataJson())
        out.put("configValidation", configValidationJson())
        out.put("configSchema", configSchemaJson())
        out
    }
}

public class MemorySearchManager {
    private let provider: MemoryProvider
    public let backendConfig: MemoryBackendConfig

    public init(provider: MemoryProvider, backendConfig: MemoryBackendConfig) {
        this.provider = provider
        this.backendConfig = backendConfig
    }

    public func resolveMemoryFiles(): Array<Path> {
        provider.resolveMemoryFiles()
    }

    public func searchRows(query: String, limit: Int64): Array<LocalMemorySearchRow> {
        provider.searchRows(query, limit)
    }

    public func searchRows(query: String, limit: Int64, sessionKey!: Option<String>): Array<LocalMemorySearchRow> {
        provider.searchRows(query, limit, sessionKey: sessionKey)
    }

    public func recordShortTermRecall(query: String, rows: Array<LocalMemoryRecallResult>): Unit {
        provider.recordShortTermRecall(query, rows)
    }

    public func statusJson(deep!: Bool): String {
        provider.statusJson(deep: deep)
    }

    public func statusText(deep!: Bool): String {
        provider.statusText(deep: deep)
    }

    public func fixArtifacts(): String {
        provider.fixArtifacts()
    }

    public func writeIndexSnapshot(): String {
        provider.writeIndexSnapshot()
    }

    public func forceReindex(): String {
        provider.forceReindex()
    }

    public func close(): Unit {}
}

public class MemorySearchManagerResult {
    public let manager: Option<MemorySearchManager>
    public let error: String

    public init(manager!: Option<MemorySearchManager> = None, error!: String = "") {
        this.manager = manager
        this.error = error
    }
}

private func externalIndexPath(): String {
    let hinted = CliConfig.externalMemoryIndexPathHint.trimAscii()
    if (!hinted.isEmpty()) {
        return hinted
    }
    MemoryPaths.indexStorePath().toString()
}

private func qmdIndexPath(): String {
    MemoryPaths.ensureWorkspaceMemoryDir()
    CliConfig.dotDir.join("memory").join("qmd").toString()
}

private let qmdRuntimeLock = Mutex()
private let qmdMaintenanceLock = Mutex()

private func qmdManagedMemoryDir(): Path {
    let dir = CliConfig.cwd.join("memory")
    if (!exists(dir)) {
        Directory.create(dir, recursive: true)
    }
    dir
}

private func qmdStateRoot(): Path {
    MemoryPaths.ensureWorkspaceMemoryDir()
    let dir = CliConfig.dotDir.join("memory").join("qmd")
    if (!exists(dir)) {
        Directory.create(dir, recursive: true)
    }
    dir
}

private func qmdConfigHome(): Path {
    let dir = qmdStateRoot().join("xdg-config")
    if (!exists(dir)) {
        Directory.create(dir, recursive: true)
    }
    dir
}

private func qmdConfigDir(): Path {
    let dir = qmdConfigHome().join("qmd")
    if (!exists(dir)) {
        Directory.create(dir, recursive: true)
    }
    dir
}

private func qmdCacheHome(): Path {
    let dir = qmdStateRoot().join("xdg-cache")
    if (!exists(dir)) {
        Directory.create(dir, recursive: true)
    }
    dir
}

private func qmdSessionExportDir(): Path {
    let configured = CliConfig.qmdSessionsExportDir.trimAscii()
    let dir = if (!configured.isEmpty()) {
        let path = Path(configured)
        if (path.isAbsolute()) { path } else { CliConfig.cwd.join(configured) }
    } else {
        qmdStateRoot().join("sessions")
    }
    if (!exists(dir)) {
        Directory.create(dir, recursive: true)
    }
    dir
}

private func qmdDefaultCollectionMask(): String {
    "MEMORY.md"
}

private func qmdNotesCollectionName(): String {
    let workspaceName = CliConfig.cwd.fileName.trimAscii()
    qmdCollectionName("memory-notes-" + workspaceName)
}

private func qmdNotesCollectionMask(): String {
    let patterns = ArrayList<String>()
    for (i in 0..CliConfig.qmdPaths.size) {
        if (i >= CliConfig.qmdPathPatterns.size) {
            continue
        }
        let candidate = CliConfig.qmdPathPatterns[i].trimAscii()
        if (!candidate.isEmpty()) {
            patterns.add(candidate)
        }
    }
    if (patterns.isEmpty()) { "**/*.md" } else { patterns[0] }
}

private func qmdSessionsCollectionMask(): String {
    "**/*.md"
}

private func qmdCollectionName(raw: String): String {
    let out = ArrayList<Rune>()
    for (ch in raw.toRuneArray()) {
        if (
            (ch >= r'a' && ch <= r'z') ||
            (ch >= r'A' && ch <= r'Z') ||
            (ch >= r'0' && ch <= r'9')
        ) {
            out.add(ch)
        } else if (ch == r'-' || ch == r'_') {
            out.add(ch)
        } else {
            out.add(r'-')
        }
    }
    let normalized = String(out.toArray()).trimAscii()
    if (normalized.isEmpty()) {
        return "memory-root"
    }
    normalized
}

private func qmdDefaultCollectionName(): String {
    let workspaceName = CliConfig.cwd.fileName.trimAscii()
    qmdCollectionName("memory-root-" + workspaceName)
}

private func qmdSessionCollectionName(): String {
    let workspaceName = CliConfig.cwd.fileName.trimAscii()
    qmdCollectionName("sessions-" + workspaceName)
}

private func qmdAddCollectionArgs(root: Path, name: String, mask!: String = ""): Array<String> {
    let args = ArrayList<String>(["collection", "add", root.toString(), "--name", name])
    let trimmedMask = mask.trimAscii()
    if (!trimmedMask.isEmpty()) {
        args.add("--mask")
        args.add(trimmedMask)
    }
    args.toArray()
}

private func qmdCommandArgs(): Array<String> {
    let values = ArrayList<String>()
    let trimmed = CliConfig.qmdCommand.trimAscii()
    if (!trimmed.isEmpty()) {
        for (piece in trimmed.split(" ")) {
            let token = piece.trimAscii()
            if (!token.isEmpty()) {
                values.add(token)
            }
        }
    }
    if (values.isEmpty()) {
        values.add("qmd")
    }
    values.toArray()
}

private func qmdConfigured(): Bool {
    !CliConfig.qmdCommand.trimAscii().isEmpty()
}

private func qmdRun(
    args: Array<String>,
    timeoutMs: Int64
): (Int64, String, String) {
    synchronized(qmdRuntimeLock) {
        let cmd = ArrayList<String>()
        cmd.add("env")
        cmd.add("XDG_CONFIG_HOME=${qmdConfigHome().toString()}")
        cmd.add("QMD_CONFIG_DIR=${qmdConfigDir().toString()}")
        cmd.add("XDG_CACHE_HOME=${qmdCacheHome().toString()}")
        for (piece in qmdCommandArgs()) {
            cmd.add(piece)
        }
        for (arg in args) {
            cmd.add(arg)
        }
        let timeout = Some(Duration.millisecond * max(1000, timeoutMs))
        ShellUtils.execute(
            cmd.toArray(),
            timeout: timeout,
            workDir: Some(CliConfig.cwd),
            withWrap: false
        )
    }
}

private func qmdEnsureCollection(root: Path, name: String, mask!: String = ""): Unit {
    let (ec, _stdout, stderr) = qmdRun(qmdAddCollectionArgs(root, name, mask: mask), CliConfig.qmdUpdateCommandTimeoutMs)
    if (ec == 0) {
        return
    }
    let lowered = stderr.toAsciiLower()
    if (
        lowered.contains("already exists") ||
        lowered.contains("a collection already exists for this path and pattern")
    ) {
        return
    }
    throw Exception("QMD collection add failed for ${name}: ${stderr.trimAscii()}")
}

private func qmdSessionsAllowedByScope(): Bool {
    isQmdScopeAllowed(Some("gateway:dm:main"))
}

private func qmdManagedCollectionNames(includeSessions!: Bool = false): Array<String> {
    let out = ArrayList<String>()
    out.add(qmdDefaultCollectionName())
    out.add(qmdNotesCollectionName())
    for (rawPath in CliConfig.qmdPaths) {
        let trimmed = rawPath.trimAscii()
        if (trimmed.isEmpty()) {
            continue
        }
        let path = Path(trimmed)
        let absolute = if (path.isAbsolute()) { path } else { CliConfig.cwd.join(trimmed) }
        out.add(qmdCollectionName("custom-" + absolute.fileName))
    }
    if (includeSessions && CliConfig.qmdSessionsEnabled && qmdSessionsAllowedByScope()) {
        out.add(qmdSessionCollectionName())
    }
    out.toArray()
}

private func qmdGatewayStore(): MemorySessionTranscriptStore {
    memorySessionStoreForGatewayUser(CliSettingManager.readGatewaySettings())
}

private func qmdRenderSessionMarkdown(sessionKey: String, content: String): String {
    let normalized = content.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
    let body = if (normalized.isEmpty()) { "(empty)" } else { normalized }
    "# Session ${MemorySessionTranscriptStore.fileStemForSessionKey(sessionKey)}\n\nsessionKey: ${sessionKey}\n\n${body}\n"
}

private func qmdExportSessions(): Int64 {
    if (!CliConfig.qmdSessionsEnabled) {
        return 0
    }
        let store = qmdGatewayStore()
        let exportDir = qmdSessionExportDir()
        let keep = ArrayList<String>()
        var exported: Int64 = 0
        let retentionCutoffMs = if (CliConfig.qmdSessionsRetentionDays > 0) {
            (DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000) - (CliConfig.qmdSessionsRetentionDays * 24 * 60 * 60 * 1000)
        } else {
            -1
        }
        for (sessionKey in store.listSessionKeys()) {
            let transcriptPath = store.transcriptPath(sessionKey)
            if (retentionCutoffMs > 0) {
                try {
                    let info = FileInfo(transcriptPath)
                    if (info.lastModificationTime.toUnixTimeStamp().toNanoseconds() / 1000000 < retentionCutoffMs) {
                        continue
                    }
                } catch (_: Exception) {
                    ()
                }
            }
            match (store.readTranscriptRaw(sessionKey)) {
                case Some(raw) =>
                let stem = MemorySessionTranscriptStore.fileStemForSessionKey(sessionKey)
                let target = exportDir.join("${stem}.md")
                let markdown = qmdRenderSessionMarkdown(sessionKey, store.formatHistoryAsText(sessionKey, 1000000))
                var shouldWrite = true
                if (exists(target)) {
                    try {
                        let current = String.fromUtf8(File.readFrom(target))
                        if (current == markdown) {
                            shouldWrite = false
                        }
                    } catch (_: Exception) {
                        shouldWrite = true
                    }
                }
                if (shouldWrite) {
                    File.writeTo(target, markdown.toArray())
                }
                keep.add(target.toString())
                if (!raw.trimAscii().isEmpty()) {
                    exported += 1
                }
            case None => ()
        }
    }
    try {
        for (entry in Directory.readFrom(exportDir)) {
            if (!entry.isRegular()) {
                continue
            }
            if (!entry.name.endsWith(".md")) {
                continue
            }
            let full = exportDir.join(entry.name).toString()
            var tracked = false
            for (kept in keep) {
                if (kept == full) {
                    tracked = true
                    break
                }
            }
            if (!tracked) {
                remove(Path(full))
            }
        }
    } catch (_: Exception) {
        ()
    }
    exported
}

private func qmdEnsureManagedCollections(): String {
    MemoryPaths.ensureWorkspaceMemoryDir()
    let _ = qmdExportSessions()
    if (CliConfig.qmdIncludeDefaultMemory) {
        qmdEnsureCollection(CliConfig.cwd, qmdDefaultCollectionName(), mask: qmdDefaultCollectionMask())
        qmdEnsureCollection(qmdManagedMemoryDir(), qmdNotesCollectionName(), mask: qmdNotesCollectionMask())
    }
    for (i in 0..CliConfig.qmdPaths.size) {
        let rawPath = CliConfig.qmdPaths[i]
        let trimmed = rawPath.trimAscii()
        if (trimmed.isEmpty()) {
            continue
        }
        let path = Path(trimmed)
        let absolute = if (path.isAbsolute()) { path } else { CliConfig.cwd.join(trimmed) }
        let explicitName = if (i < CliConfig.qmdPathNames.size) { CliConfig.qmdPathNames[i].trimAscii() } else { "" }
        let pattern = if (i < CliConfig.qmdPathPatterns.size) { CliConfig.qmdPathPatterns[i].trimAscii() } else { "" }
        let collectionName = if (!explicitName.isEmpty()) { qmdCollectionName(explicitName) } else { qmdCollectionName("custom-" + absolute.fileName) }
        qmdEnsureCollection(absolute, collectionName, mask: pattern)
    }
    if (CliConfig.qmdSessionsEnabled) {
        qmdEnsureCollection(qmdSessionExportDir(), qmdSessionCollectionName(), mask: qmdSessionsCollectionMask())
    }
    qmdStateRoot().toString()
}

private func qmdRunUpdate(): (Int64, String, String) {
    qmdRun(["update"], CliConfig.qmdUpdateUpdateTimeoutMs)
}

private func qmdParseLineNumber(value: JsonValue, fallback: Int64): Int64 {
    match (value) {
        case v: JsonString => externalParseInt64Or(v.getValue(), fallback)
        case _ => externalParseInt64Or(value.toString(), fallback)
    }
}

private func qmdParseSearchRows(stdout: String): Array<LocalMemorySearchRow> {
    let rows = ArrayList<LocalMemorySearchRow>()
    let parsed = try {
        JsonValue.fromStr(stdout)
    } catch (_e: Exception) {
        return rows.toArray()
    }
    let arr = match (parsed) {
        case value: JsonArray => value
        case value: JsonObject =>
            match (value.get("results")) {
                case Some(v: JsonArray) => v
                case _ =>
                    match (value.get("hits")) {
                        case Some(v: JsonArray) => v
                        case _ => JsonArray([])
                    }
            }
        case _ => JsonArray([])
    }
    for (item in arr.getItems()) {
        match (item) {
            case obj: JsonObject =>
                let path = match (obj.get("path")) {
                    case Some(v: JsonString) => v.getValue().trimAscii()
                    case _ =>
                        match (obj.get("file")) {
                            case Some(v: JsonString) => v.getValue().trimAscii()
                            case _ => ""
                        }
                }
                let text = match (obj.get("text")) {
                    case Some(v: JsonString) => v.getValue()
                    case _ =>
                        match (obj.get("snippet")) {
                            case Some(v: JsonString) => v.getValue()
                            case _ => ""
                        }
                }
                let startLine = match (obj.get("startLine")) {
                    case Some(v) => qmdParseLineNumber(v, 1)
                    case _ =>
                        match (obj.get("start_line")) {
                            case Some(v) => qmdParseLineNumber(v, 1)
                            case _ => 1
                        }
                }
                let endLine = match (obj.get("endLine")) {
                    case Some(v) => qmdParseLineNumber(v, startLine)
                    case _ =>
                        match (obj.get("end_line")) {
                            case Some(v) => qmdParseLineNumber(v, startLine)
                            case _ => startLine
                        }
                }
                if (!path.isEmpty() && !text.trimAscii().isEmpty()) {
                    rows.add(LocalMemorySearchRow(path, startLine, max(startLine, endLine), text))
                }
            case _ => ()
        }
    }
    rows.toArray()
}

private func qmdSearchCommand(mode: String, query: String, limit: Int64): Array<String> {
    let args = ArrayList<String>()
    let explicitTool = CliConfig.qmdSearchTool.trimAscii().toAsciiLower()
    let normalized = if (!explicitTool.isEmpty()) { explicitTool } else { mode.trimAscii().toAsciiLower() }
    let sub = if (normalized == "vsearch") {
        "vsearch"
    } else if (normalized == "query") {
        "query"
    } else {
        "search"
    }
    args.add(sub)
    args.add(query)
    args.add("--json")
    args.add("--limit")
    args.add("${limit}")
    for (collection in qmdManagedCollectionNames(includeSessions: qmdSessionsAllowedByScope())) {
        args.add("--collection")
        args.add(collection)
    }
    args.toArray()
}

private func externalParseInt64Or(text: String, fallback: Int64): Int64 {
    try {
        Int64.parse(text)
    } catch (_e: Exception) {
        fallback
    }
}

private func parseExternalSearchRows(stdout: String): Array<LocalMemorySearchRow> {
    let rows = ArrayList<LocalMemorySearchRow>()
    let parsed = try {
        JsonValue.fromStr(stdout)
    } catch (_e: Exception) {
        return rows.toArray()
    }
    let root = parsed.asObject()
    match (root.get("results")) {
        case Some(value) =>
            let arr = value.asArray()
            for (item in arr.getItems()) {
                match (item) {
                    case obj: JsonObject =>
                        let path = match (obj.get("path")) {
                            case Some(v: JsonString) => v.getValue().trimAscii()
                            case _ => ""
                        }
                        let text = match (obj.get("text")) {
                            case Some(v: JsonString) => v.getValue()
                            case _ => ""
                        }
                        let startLine = match (obj.get("startLine")) {
                            case Some(v) => externalParseInt64Or(v.toString(), 1)
                            case _ => 1
                        }
                        let endLine = match (obj.get("endLine")) {
                            case Some(v) => externalParseInt64Or(v.toString(), startLine)
                            case _ => startLine
                        }
                        if (!path.isEmpty() && !text.trimAscii().isEmpty()) {
                            rows.add(LocalMemorySearchRow(path, startLine, max(startLine, endLine), text))
                        }
                    case _ => ()
                }
            }
        case _ => ()
    }
    rows.toArray()
}

public interface MemoryOrchestrationBackend {
    func backendId(): String
    func previewPromote(limit!: Int64, includePromoted!: Bool, minScore!: Float64, minRecallCount!: Int64, minUniqueQueries!: Int64): String
    func previewPromoteJson(limit!: Int64, includePromoted!: Bool, minScore!: Float64, minRecallCount!: Int64, minUniqueQueries!: Int64): String
    func explainPromote(selector: String, json!: Bool, limit!: Int64, includePromoted!: Bool, minScore!: Float64, minRecallCount!: Int64, minUniqueQueries!: Int64): String
    func applyPromote(limit!: Int64, includePromoted!: Bool, minScore!: Float64, minRecallCount!: Int64, minUniqueQueries!: Int64): String
    func previewRemHarness(json!: Bool, includePromoted!: Bool): String
    func applyRemHarness(includePromoted!: Bool, limit!: Int64, lookbackDays!: Int64): String
    func applyLightDreaming(includePromoted!: Bool, limit!: Int64, lookbackDays!: Int64): String
    func applyDeepDreaming(includePromoted!: Bool, limit!: Int64, lookbackDays!: Int64): String
    func applyDreamingSweep(includePromoted!: Bool): String
}

private func providerTokenizeQuery(query: String): Array<String> {
    let tokens = ArrayList<String>()
    for (piece in query.toAsciiLower().split(" ")) {
        let token = piece.trimAscii()
        if (!token.isEmpty()) {
            tokens.add(token)
        }
    }
    if (tokens.isEmpty()) {
        let trimmed = query.trimAscii().toAsciiLower()
        if (!trimmed.isEmpty()) {
            tokens.add(trimmed)
        }
    }
    tokens.toArray()
}

private func providerCountMatches(text: String, token: String): Int64 {
    if (token.isEmpty()) {
        return 0
    }
    var count: Int64 = 0
    var start: Int64 = 0
    while (start < text.size) {
        match (text.indexOf(token, start)) {
            case Some(found) =>
                count += 1
                start = found + token.size
            case None =>
                break
        }
    }
    count
}

private func providerComputeLineScore(lineLower: String, tokens: Array<String>): Float64 {
    var score = 0.0
    for (token in tokens) {
        let matches = providerCountMatches(lineLower, token)
        if (matches > 0) {
            score += Float64(matches)
        }
    }
    score
}

private func providerExcerptLines(lines: Array<String>, startLine: Int64, endLine: Int64): String {
    let out = ArrayList<String>()
    for (lineNo in startLine..=endLine) {
        let idx = lineNo - 1
        if (idx < 0 || idx >= lines.size) {
            continue
        }
        out.add("${lineNo}: ${lines[idx]}")
    }
    String.join(out.toArray(), delimiter: "\n")
}

private func providerStatusJson(
    providerId: String,
    backend: String,
    manualReindexSupported: Bool,
    deep: Bool
): String {
    let purpose = if (deep) { "provider-status-deep" } else { "provider-status" }
    let parsed = JsonValue.fromStr(
        LocalMemoryIndexManager.buildStatusJson(agentId: "", purpose: purpose, deep: deep)
    )
    match (parsed) {
        case obj: JsonObject =>
            obj.put("provider", JsonString(providerId))
            obj.put("backend", JsonString(backend))
            obj.put("manualReindexSupported", manualReindexSupported.toJsonValue())
            obj.toJsonString()
        case _ =>
            LocalMemoryIndexManager.buildStatusJson(agentId: "", purpose: purpose, deep: deep)
    }
}

private func providerStatusText(
    providerId: String,
    backend: String,
    manualReindexSupported: Bool,
    deep: Bool
): String {
    let purpose = if (deep) { "provider-status-deep" } else { "provider-status" }
    let base = LocalMemoryIndexManager.buildStatusText(agentId: "", purpose: purpose, deep: deep)
    let replaced = ArrayList<String>()
    var replacedBackend = false
    var replacedProvider = false
    for (line in base.split("\n")) {
        if (line.startsWith("Memory backend: ")) {
            replaced.add("Memory backend: ${backend}")
            replacedBackend = true
        } else if (line.startsWith("Memory provider: ")) {
            replaced.add("Memory provider: ${providerId}")
            replacedProvider = true
        } else {
            replaced.add(line)
        }
    }
    let lines = ArrayList<String>()
    if (!replacedBackend) {
        lines.add("Memory backend: ${backend}")
    }
    if (!replacedProvider) {
        lines.add("Memory provider: ${providerId}")
    }
    for (line in replaced) {
        lines.add(line)
    }
    lines.add("Manual reindex supported: ${manualReindexSupported}")
    String.join(lines.toArray(), delimiter: "\n")
}

private func providerWorkspaceRelativePath(path: Path): String {
    let workspace = CliConfig.cwd.toString().replace("\\", "/")
    let full = path.toString().replace("\\", "/")
    let prefix = workspace + "/"
    if (full.startsWith(prefix)) {
        return full[prefix.size..]
    }
    if (full == workspace) {
        return path.fileName
    }
    full
}

public interface MemoryProvider {
    func providerId(): String
    func backendId(): String
    func manualReindexSupported(): Bool

    func searchEnabled(): Bool
    func indexPath(): String
    func resolveMemoryFiles(): Array<Path>
    func searchRows(query: String, limit: Int64): Array<LocalMemorySearchRow>
    func searchRows(query: String, limit: Int64, sessionKey!: Option<String>): Array<LocalMemorySearchRow>
    func recordShortTermRecall(query: String, rows: Array<LocalMemoryRecallResult>): Unit

    func statusJson(deep!: Bool): String
    func statusText(deep!: Bool): String
    func fixArtifacts(): String
    func writeIndexSnapshot(): String
    func forceReindex(): String
}

private class LocalMemoryOrchestrationBackend <: MemoryOrchestrationBackend {
    public func backendId(): String {
        "local-memory-orchestration"
    }

    public func previewPromote(limit!: Int64, includePromoted!: Bool, minScore!: Float64, minRecallCount!: Int64, minUniqueQueries!: Int64): String {
        LocalMemoryIndexManager.previewPromote(
            limit: limit,
            includePromoted: includePromoted,
            minScore: minScore,
            minRecallCount: minRecallCount,
            minUniqueQueries: minUniqueQueries
        )
    }

    public func previewPromoteJson(limit!: Int64, includePromoted!: Bool, minScore!: Float64, minRecallCount!: Int64, minUniqueQueries!: Int64): String {
        LocalMemoryIndexManager.previewPromoteJson(
            limit: limit,
            includePromoted: includePromoted,
            minScore: minScore,
            minRecallCount: minRecallCount,
            minUniqueQueries: minUniqueQueries
        )
    }

    public func explainPromote(selector: String, json!: Bool, limit!: Int64, includePromoted!: Bool, minScore!: Float64, minRecallCount!: Int64, minUniqueQueries!: Int64): String {
        LocalMemoryIndexManager.explainPromote(
            selector,
            json: json,
            limit: limit,
            includePromoted: includePromoted,
            minScore: minScore,
            minRecallCount: minRecallCount,
            minUniqueQueries: minUniqueQueries
        )
    }

    public func applyPromote(limit!: Int64, includePromoted!: Bool, minScore!: Float64, minRecallCount!: Int64, minUniqueQueries!: Int64): String {
        LocalMemoryIndexManager.applyPromote(
            limit: limit,
            includePromoted: includePromoted,
            minScore: minScore,
            minRecallCount: minRecallCount,
            minUniqueQueries: minUniqueQueries
        )
    }

    public func previewRemHarness(json!: Bool, includePromoted!: Bool): String {
        LocalMemoryIndexManager.previewRemHarness(json: json, includePromoted: includePromoted)
    }

    public func applyRemHarness(includePromoted!: Bool, limit!: Int64, lookbackDays!: Int64): String {
        LocalMemoryIndexManager.applyRemHarness(
            includePromoted: includePromoted,
            limit: limit,
            lookbackDays: lookbackDays
        )
    }

    public func applyLightDreaming(includePromoted!: Bool, limit!: Int64, lookbackDays!: Int64): String {
        LocalMemoryIndexManager.applyLightDreaming(
            includePromoted: includePromoted,
            limit: limit,
            lookbackDays: lookbackDays
        )
    }

    public func applyDeepDreaming(includePromoted!: Bool, limit!: Int64, lookbackDays!: Int64): String {
        LocalMemoryIndexManager.applyDeepDreaming(
            includePromoted: includePromoted,
            limit: limit,
            lookbackDays: lookbackDays
        )
    }

    public func applyDreamingSweep(includePromoted!: Bool): String {
        LocalMemoryIndexManager.applyDreamingSweep(includePromoted: includePromoted)
    }
}

private class LocalMemoryProvider <: MemoryProvider {
    public func providerId(): String {
        "local"
    }

    public func backendId(): String {
        "sqlite-fts+local-file"
    }

    public func manualReindexSupported(): Bool {
        true
    }

    public func searchEnabled(): Bool {
        true
    }

    public func indexPath(): String {
        MemoryPaths.indexStorePath().toString()
    }

    public func resolveMemoryFiles(): Array<Path> {
        LocalMemoryIndexManager.resolveMemoryFiles()
    }

    public func searchRows(query: String, limit: Int64): Array<LocalMemorySearchRow> {
        this.searchRows(query, limit, sessionKey: None)
    }

    public func searchRows(query: String, limit: Int64, sessionKey!: Option<String>): Array<LocalMemorySearchRow> {
        LocalMemoryIndexManager.searchSqlite(query, limit)
    }

    public func recordShortTermRecall(query: String, rows: Array<LocalMemoryRecallResult>): Unit {
        LocalMemoryIndexManager.recordShortTermRecall(query, rows)
    }

    public func statusJson(deep!: Bool): String {
        providerStatusJson(providerId(), backendId(), manualReindexSupported(), deep)
    }

    public func statusText(deep!: Bool): String {
        providerStatusText(providerId(), backendId(), manualReindexSupported(), deep)
    }

    public func fixArtifacts(): String {
        LocalMemoryIndexManager.fixArtifacts()
    }

    public func writeIndexSnapshot(): String {
        LocalMemoryIndexManager.writeIndexSnapshot()
    }

    public func forceReindex(): String {
        LocalMemoryIndexManager.forceReindex()
    }
}

private class LocalCompatMemoryProvider <: MemoryProvider {
    public func providerId(): String {
        "builtin"
    }

    public func backendId(): String {
        "builtin-file"
    }

    public func manualReindexSupported(): Bool {
        false
    }

    public func searchEnabled(): Bool {
        true
    }

    public func indexPath(): String {
        MemoryPaths.indexStorePath().toString()
    }

    public func resolveMemoryFiles(): Array<Path> {
        LocalMemoryIndexManager.resolveMemoryFiles()
    }

    public func searchRows(query: String, limit: Int64): Array<LocalMemorySearchRow> {
        this.searchRows(query, limit, sessionKey: None)
    }

    public func searchRows(query: String, limit: Int64, sessionKey!: Option<String>): Array<LocalMemorySearchRow> {
        let tokens = providerTokenizeQuery(query)
        let hits = ArrayList<LocalMemorySearchRow>()
        for (filePath in LocalMemoryIndexManager.resolveMemoryFiles()) {
            let relPath = providerWorkspaceRelativePath(filePath)
            let content = String.fromUtf8(File.readFrom(filePath)).replace("\r\n", "\n").replace("\r", "\n")
            let lines = content.split("\n")
            for (i in 0..lines.size) {
                let line = lines[i]
                let score = providerComputeLineScore(line.toAsciiLower(), tokens)
                if (score <= 0.0) {
                    continue
                }
                let lineNo = i + 1
                let startLine = if (lineNo > 1) { lineNo - 1 } else { lineNo }
                let endLine = if (lineNo < lines.size) { lineNo + 1 } else { lineNo }
                hits.add(
                    LocalMemorySearchRow(
                        relPath,
                        startLine,
                        endLine,
                        providerExcerptLines(lines, startLine, endLine)
                    )
                )
            }
        }
        let ordered = hits.toArray()
        sort(ordered, by: { a, b =>
            let aScore = providerComputeLineScore(a.text.toAsciiLower(), tokens)
            let bScore = providerComputeLineScore(b.text.toAsciiLower(), tokens)
            if (aScore == bScore) {
                a.path.compare(b.path)
            } else {
                if (aScore > bScore) {
                    Ordering.LT
                } else {
                    Ordering.GT
                }
            }
        }, stable: true)
        if (ordered.size <= limit) {
            return ordered
        }
        ordered[0..limit]
    }

    public func recordShortTermRecall(query: String, rows: Array<LocalMemoryRecallResult>): Unit {
        LocalMemoryIndexManager.recordShortTermRecall(query, rows)
    }

    public func statusJson(deep!: Bool): String {
        providerStatusJson(providerId(), backendId(), manualReindexSupported(), deep)
    }

    public func statusText(deep!: Bool): String {
        providerStatusText(providerId(), backendId(), manualReindexSupported(), deep)
    }

    public func fixArtifacts(): String {
        LocalMemoryIndexManager.fixArtifacts()
    }

    public func writeIndexSnapshot(): String {
        LocalMemoryIndexManager.writeIndexSnapshot()
    }

    public func forceReindex(): String {
        "Memory backend does not support manual reindex."
    }
}

private class ExternalCommandMemoryProvider <: MemoryProvider {
    private func configured(): Bool {
        !CliConfig.externalMemoryCommand.trimAscii().isEmpty()
    }

    private func commandArgs(query: String, limit: Int64): Array<String> {
        let args = ArrayList<String>()
        args.add(CliConfig.externalMemoryCommand.trimAscii())
        for (arg in CliConfig.externalMemoryArgs) {
            let trimmed = arg.trimAscii()
            if (!trimmed.isEmpty()) {
                args.add(trimmed)
            }
        }
        args.add("--query")
        args.add(query)
        args.add("--limit")
        args.add("${limit}")
        args.toArray()
    }

    public func providerId(): String {
        "external"
    }

    public func backendId(): String {
        CliConfig.externalMemoryBackendLabel
    }

    public func manualReindexSupported(): Bool {
        false
    }

    public func searchEnabled(): Bool {
        configured()
    }

    public func indexPath(): String {
        externalIndexPath()
    }

    public func resolveMemoryFiles(): Array<Path> {
        Array<Path>()
    }

    public func searchRows(query: String, limit: Int64): Array<LocalMemorySearchRow> {
        this.searchRows(query, limit, sessionKey: None)
    }

    public func searchRows(query: String, limit: Int64, sessionKey!: Option<String>): Array<LocalMemorySearchRow> {
        if (!configured()) {
            return Array<LocalMemorySearchRow>()
        }
        try {
            let timeout = Some(Duration.millisecond * max(1000, CliConfig.externalMemoryTimeoutMs))
            let (ec, stdout, _stderr) = ShellUtils.execute(
                commandArgs(query, limit),
                timeout: timeout,
                workDir: Some(CliConfig.cwd),
                withWrap: false
            )
            if (ec != 0) {
                return Array<LocalMemorySearchRow>()
            }
            parseExternalSearchRows(stdout)
        } catch (_e: Exception) {
            Array<LocalMemorySearchRow>()
        }
    }

    public func recordShortTermRecall(query: String, rows: Array<LocalMemoryRecallResult>): Unit {
        LocalMemoryIndexManager.recordShortTermRecall(query, rows)
    }

    public func statusJson(deep!: Bool): String {
        providerStatusJson(providerId(), backendId(), manualReindexSupported(), deep)
    }

    public func statusText(deep!: Bool): String {
        providerStatusText(providerId(), backendId(), manualReindexSupported(), deep)
    }

    public func fixArtifacts(): String {
        LocalMemoryIndexManager.fixArtifacts()
    }

    public func writeIndexSnapshot(): String {
        if (!configured()) {
            return "External memory backend is not configured."
        }
        "External memory backend does not support manual index snapshot writes."
    }

    public func forceReindex(): String {
        if (!configured()) {
            return "External memory backend is not configured."
        }
        "External memory backend does not support manual reindex."
    }
}

private class QmdMemoryProvider <: MemoryProvider {
    public func providerId(): String {
        "qmd"
    }

    public func backendId(): String {
        "qmd"
    }

    public func manualReindexSupported(): Bool {
        true
    }

    public func searchEnabled(): Bool {
        qmdConfigured()
    }

    public func indexPath(): String {
        qmdIndexPath()
    }

    public func resolveMemoryFiles(): Array<Path> {
        LocalMemoryIndexManager.resolveMemoryFiles()
    }

    public func searchRows(query: String, limit: Int64): Array<LocalMemorySearchRow> {
        this.searchRows(query, limit, sessionKey: None)
    }

    public func searchRows(query: String, limit: Int64, sessionKey!: Option<String>): Array<LocalMemorySearchRow> {
        QmdBackendRuntime.searchRows(query, limit, sessionKey: sessionKey)
    }

    public func recordShortTermRecall(query: String, rows: Array<LocalMemoryRecallResult>): Unit {
        LocalMemoryIndexManager.recordShortTermRecall(query, rows)
    }

    public func statusJson(deep!: Bool): String {
        QmdBackendRuntime.statusJson(providerId(), backendId(), manualReindexSupported(), deep)
    }

    public func statusText(deep!: Bool): String {
        QmdBackendRuntime.statusText(providerId(), backendId(), manualReindexSupported(), deep)
    }

    public func fixArtifacts(): String {
        QmdBackendRuntime.fixArtifacts()
    }

    public func writeIndexSnapshot(): String {
        QmdBackendRuntime.writeIndexSnapshot()
    }

    public func forceReindex(): String {
        writeIndexSnapshot()
    }
}

private class MemoryBackendAdapterRegistry {
    private static var searchBackends = HashMap<String, MemoryProvider>()
    private static var orchestrationBackends = HashMap<String, MemoryOrchestrationBackend>()
    private static var bootstrapped = false

    private static func ensureBootstrapped(): Unit {
        if (bootstrapped) {
            return
        }
        bootstrapped = true
        registerSearch(LocalMemoryProvider())
        registerSearch(LocalCompatMemoryProvider())
        registerSearch(ExternalCommandMemoryProvider())
        registerSearch(QmdMemoryProvider())
        registerOrchestration(LocalMemoryOrchestrationBackend(), backendId: "local")
    }

    public static func registerSearch(provider: MemoryProvider): Unit {
        let pid = provider.providerId().trimAscii()
        if (pid.isEmpty()) {
            return
        }
        searchBackends[pid] = provider
    }

    public static func registerOrchestration(backend: MemoryOrchestrationBackend, backendId!: String = ""): Unit {
        let bid = if (backendId.trimAscii().isEmpty()) { backend.backendId().trimAscii() } else { backendId.trimAscii() }
        if (bid.isEmpty()) {
            return
        }
        orchestrationBackends[bid] = backend
    }

    public static func registeredSearchProviderIds(): Array<String> {
        ensureBootstrapped()
        let out = ArrayList<String>()
        for ((pid, _provider) in searchBackends) {
            out.add(pid)
        }
        out.toArray()
    }

    public static func registeredSearchBackendConfigs(): Array<MemoryBackendConfig> {
        ensureBootstrapped()
        let out = ArrayList<MemoryBackendConfig>()
        for ((_pid, provider) in searchBackends) {
            out.add(
                MemoryBackendConfig(
                    provider.providerId(),
                    provider.backendId(),
                    provider.searchEnabled(),
                    provider.manualReindexSupported(),
                    provider.indexPath()
                )
            )
        }
        out.toArray()
    }

    public static func resolveSearchProvider(providerId: String): Option<MemoryProvider> {
        ensureBootstrapped()
        searchBackends.get(providerId.trimAscii())
    }

    public static func resolveSearchProviderSelection(
        providerOrBackendId: String
    ): (Option<MemoryProvider>, String) {
        ensureBootstrapped()
        let normalized = providerOrBackendId.trimAscii()
        if (normalized.isEmpty()) {
            return (None, "")
        }
        match (searchBackends.get(normalized)) {
            case Some(provider) => (Some(provider), "provider-id")
            case None =>
                var matched = None<MemoryProvider>
                for ((_pid, provider) in searchBackends) {
                    if (provider.backendId().trimAscii() != normalized) {
                        continue
                    }
                    matched = Some(provider)
                    break
                }
                (matched, if (matched.isSome()) { "backend-id" } else { "" })
        }
    }

    public static func resolveOrchestrationBackend(backendId: String): Option<MemoryOrchestrationBackend> {
        ensureBootstrapped()
        orchestrationBackends.get(backendId.trimAscii())
    }

    public static func registeredOrchestrationBackendIds(): Array<String> {
        ensureBootstrapped()
        let out = ArrayList<String>()
        for ((bid, _backend) in orchestrationBackends) {
            out.add(bid)
        }
        out.toArray()
    }
}

private class QmdBackendRuntime {
    public static func searchRows(query: String, limit: Int64, sessionKey!: Option<String>): Array<LocalMemorySearchRow> {
        if (!qmdConfigured()) {
            return Array<LocalMemorySearchRow>()
        }
        try {
            let _ = qmdEnsureManagedCollections()
            if (!isQmdScopeAllowed(sessionKey)) {
                let info = deriveQmdScopeInfo(sessionKey)
                LogUtils.info("qmd search denied by scope (channel=${info.channel ?? "-"}, chatType=${info.chatType ?? "-"}, session=${sessionKey ?? ""})")
                return Array<LocalMemorySearchRow>()
            }
            let effectiveLimit = min(max(1, limit), max(1, CliConfig.qmdLimitsMaxResults))
            let (ec, stdout, _stderr) = qmdRun(
                qmdSearchCommand(CliConfig.qmdSearchMode, query, effectiveLimit),
                CliConfig.qmdLimitsTimeoutMs
            )
            if (ec == 0) {
                let parsed = qmdParseSearchRows(stdout)
                if (!parsed.isEmpty()) {
                    return parsed
                }
            }
            let (updateEc, _updateOut, _updateErr) = qmdRunUpdate()
            if (updateEc == 0) {
                let (retryEc, retryOut, _retryErr) = qmdRun(
                    qmdSearchCommand(CliConfig.qmdSearchMode, query, effectiveLimit),
                    CliConfig.qmdLimitsTimeoutMs
                )
                if (retryEc == 0) {
                    let parsed = qmdParseSearchRows(retryOut)
                    if (!parsed.isEmpty()) {
                        return parsed
                    }
                }
            }
            if (CliConfig.qmdSearchMode.trimAscii().toAsciiLower() != "query") {
                let (fallbackEc, fallbackOut, _fallbackErr) = qmdRun(
                    qmdSearchCommand("query", query, effectiveLimit),
                    CliConfig.qmdLimitsTimeoutMs
                )
                if (fallbackEc == 0) {
                    return qmdParseSearchRows(fallbackOut)
                }
            }
            Array<LocalMemorySearchRow>()
        } catch (_e: Exception) {
            Array<LocalMemorySearchRow>()
        }
    }

    public static func statusJson(providerId: String, backendId: String, manualReindexSupported: Bool, deep: Bool): String {
        let parsed = JsonValue.fromStr(providerStatusJson(providerId, backendId, manualReindexSupported, deep))
        match (parsed) {
            case obj: JsonObject =>
                var qmdStatus = "unavailable"
                var qmdStatusOutput = ""
                let exportedSessions = if (CliConfig.qmdSessionsEnabled) { qmdExportSessions() } else { 0 }
                if (qmdConfigured()) {
                    try {
                        let (ec, stdout, stderr) = qmdRun(["status"], CliConfig.qmdUpdateCommandTimeoutMs)
                        qmdStatus = if (ec == 0) { "ok" } else { "error" }
                        qmdStatusOutput = if (!stdout.trimAscii().isEmpty()) { stdout } else { stderr }
                    } catch (e: Exception) {
                        qmdStatus = "error"
                        qmdStatusOutput = e.message
                    }
                }
                obj.put("qmdCommand", JsonString(CliConfig.qmdCommand))
                obj.put("qmdSearchMode", JsonString(CliConfig.qmdSearchMode))
                obj.put("qmdSearchTool", JsonString(CliConfig.qmdSearchTool))
                obj.put("memoryCitations", JsonString(CliConfig.memoryCitations))
                obj.put("qmdIncludeDefaultMemory", CliConfig.qmdIncludeDefaultMemory.toJsonValue())
                obj.put("qmdSessionsEnabled", CliConfig.qmdSessionsEnabled.toJsonValue())
                obj.put("qmdSessionsExportDir", JsonString(CliConfig.qmdSessionsExportDir))
                obj.put("qmdSessionsRetentionDays", CliConfig.qmdSessionsRetentionDays.toJsonValue())
                obj.put("qmdUpdateOnBoot", CliConfig.qmdUpdateOnBoot.toJsonValue())
                obj.put("qmdUpdateWaitForBootSync", CliConfig.qmdUpdateWaitForBootSync.toJsonValue())
                obj.put("qmdUpdateIntervalMs", CliConfig.qmdUpdateIntervalMs.toJsonValue())
                obj.put("qmdUpdateDebounceMs", CliConfig.qmdUpdateDebounceMs.toJsonValue())
                obj.put("qmdUpdateEmbedIntervalMs", CliConfig.qmdUpdateEmbedIntervalMs.toJsonValue())
                obj.put("qmdUpdateCommandTimeoutMs", CliConfig.qmdUpdateCommandTimeoutMs.toJsonValue())
                obj.put("qmdUpdateUpdateTimeoutMs", CliConfig.qmdUpdateUpdateTimeoutMs.toJsonValue())
                obj.put("qmdUpdateEmbedTimeoutMs", CliConfig.qmdUpdateEmbedTimeoutMs.toJsonValue())
                obj.put("qmdLimitsMaxResults", CliConfig.qmdLimitsMaxResults.toJsonValue())
                obj.put("qmdLimitsMaxSnippetChars", CliConfig.qmdLimitsMaxSnippetChars.toJsonValue())
                obj.put("qmdLimitsMaxInjectedChars", CliConfig.qmdLimitsMaxInjectedChars.toJsonValue())
                obj.put("qmdLimitsTimeoutMs", CliConfig.qmdLimitsTimeoutMs.toJsonValue())
                obj.put("qmdScopeDefault", JsonString(CliConfig.qmdScopeDefault))
                obj.put("qmdMcporterStartDaemon", CliConfig.qmdMcporterStartDaemon.toJsonValue())
                obj.put("qmdMcporterEnabled", CliConfig.qmdMcporterEnabled.toJsonValue())
                obj.put("qmdMcporterServerName", JsonString(CliConfig.qmdMcporterServerName))
                obj.put("qmdStateRoot", JsonString(qmdStateRoot().toString()))
                obj.put("qmdSessionExportDir", JsonString(qmdSessionExportDir().toString()))
                obj.put("qmdDefaultCollection", JsonString(qmdDefaultCollectionName()))
                obj.put("qmdNotesCollection", JsonString(qmdNotesCollectionName()))
                obj.put("qmdSessionCollection", JsonString(qmdSessionCollectionName()))
                obj.put("qmdSessionsAllowedByScope", qmdSessionsAllowedByScope().toJsonValue())
                obj.put("qmdExportedSessionCount", exportedSessions.toJsonValue())
                let paths = ArrayList<JsonValue>()
                for (path in CliConfig.qmdPaths) {
                    paths.add(JsonString(path))
                }
                obj.put("qmdPaths", JsonArray(paths.toArray()))
                obj.put("qmdStatus", JsonString(qmdStatus))
                obj.put("qmdStatusOutput", JsonString(qmdStatusOutput))
                obj.put("compatNote", JsonString("Native qmd provider supports managed collections, session export, scope-gated session recall, boot maintenance, and manual update/embed indexing. Mcporter routing remains config-only."))
                obj.toJsonString()
            case _ =>
                providerStatusJson(providerId, backendId, manualReindexSupported, deep)
        }
    }

    public static func statusText(providerId: String, backendId: String, manualReindexSupported: Bool, deep: Bool): String {
        let lines = ArrayList<String>()
        lines.add(providerStatusText(providerId, backendId, manualReindexSupported, deep))
        lines.add("QMD command: ${CliConfig.qmdCommand}")
        lines.add("Memory citations: ${CliConfig.memoryCitations}")
        lines.add("QMD search mode: ${CliConfig.qmdSearchMode}")
        if (!CliConfig.qmdSearchTool.trimAscii().isEmpty()) {
            lines.add("QMD search tool: ${CliConfig.qmdSearchTool}")
        }
        lines.add("QMD include default memory: ${CliConfig.qmdIncludeDefaultMemory}")
        lines.add("QMD sessions enabled: ${CliConfig.qmdSessionsEnabled}")
        if (!CliConfig.qmdSessionsExportDir.trimAscii().isEmpty()) {
            lines.add("QMD sessions export dir override: ${CliConfig.qmdSessionsExportDir}")
        }
        if (CliConfig.qmdSessionsRetentionDays > 0) {
            lines.add("QMD sessions retention days: ${CliConfig.qmdSessionsRetentionDays}")
        }
        lines.add("QMD update on boot: ${CliConfig.qmdUpdateOnBoot}")
        lines.add("QMD wait for boot sync: ${CliConfig.qmdUpdateWaitForBootSync}")
        lines.add("QMD update interval ms: ${CliConfig.qmdUpdateIntervalMs}")
        lines.add("QMD update debounce ms: ${CliConfig.qmdUpdateDebounceMs}")
        lines.add("QMD embed interval ms: ${CliConfig.qmdUpdateEmbedIntervalMs}")
        lines.add("QMD limits max results: ${CliConfig.qmdLimitsMaxResults}")
        lines.add("QMD limits max snippet chars: ${CliConfig.qmdLimitsMaxSnippetChars}")
        lines.add("QMD limits max injected chars: ${CliConfig.qmdLimitsMaxInjectedChars}")
        lines.add("QMD limits timeout ms: ${CliConfig.qmdLimitsTimeoutMs}")
        lines.add("QMD scope default: ${CliConfig.qmdScopeDefault}")
        lines.add("QMD mcporter enabled: ${CliConfig.qmdMcporterEnabled}")
        lines.add("QMD mcporter server: ${CliConfig.qmdMcporterServerName}")
        lines.add("QMD mcporter start daemon: ${CliConfig.qmdMcporterStartDaemon}")
        lines.add("QMD state root: ${qmdStateRoot().toString()}")
        lines.add("QMD default collection: ${qmdDefaultCollectionName()}")
        lines.add("QMD notes collection: ${qmdNotesCollectionName()}")
        lines.add("QMD sessions allowed by scope: ${qmdSessionsAllowedByScope()}")
        if (CliConfig.qmdSessionsEnabled) {
            lines.add("QMD session export dir: ${qmdSessionExportDir().toString()}")
            lines.add("QMD session collection: ${qmdSessionCollectionName()}")
            lines.add("QMD exported sessions: ${qmdExportSessions()}")
        }
        if (CliConfig.qmdPaths.size > 0) {
            let joinedPaths = String.join(CliConfig.qmdPaths, delimiter: "; ")
            lines.add("QMD paths: ${joinedPaths}")
        }
        if (qmdConfigured()) {
            try {
                let (ec, stdout, stderr) = qmdRun(["status"], CliConfig.qmdUpdateCommandTimeoutMs)
                lines.add("QMD status: ${if (ec == 0) { "ok" } else { "error" }}")
                let output = if (!stdout.trimAscii().isEmpty()) { stdout.trimAscii() } else { stderr.trimAscii() }
                if (!output.isEmpty()) {
                    lines.add("QMD status output: ${output}")
                }
            } catch (e: Exception) {
                lines.add("QMD status: error")
                lines.add("QMD status output: ${e.message}")
            }
        } else {
            lines.add("QMD status: unavailable")
        }
        String.join(lines.toArray(), delimiter: "\n")
    }

    public static func fixArtifacts(): String {
        let fixes = ArrayList<String>()
        let _ = LocalMemoryIndexManager.fixArtifacts()
        let _ = qmdStateRoot()
        let _ = qmdConfigHome()
        let _ = qmdConfigDir()
        let _ = qmdCacheHome()
        if (CliConfig.qmdSessionsEnabled) {
            let _ = qmdSessionExportDir()
            let exported = qmdExportSessions()
            fixes.add("exported ${exported} gateway sessions for qmd")
        }
        fixes.add("ensured qmd state directories")
        String.join(fixes.toArray(), delimiter: "\n")
    }

    public static func writeIndexSnapshot(): String {
        if (!qmdConfigured()) {
            return "QMD provider is not configured."
        }
        try {
            let root = qmdEnsureManagedCollections()
            MemoryProviderRegistry.runQmdMaintenanceCycle("manual-index", embed: true)
            root
        } catch (e: Exception) {
            "QMD index failed: ${e.message}"
        }
    }
}

private class QmdMaintenanceRuntime {
    private static var maintenanceFuture: Option<Future<Unit>> = None
    private static var lastUpdateAtMs: Int64 = 0
    private static var lastEmbedAtMs: Int64 = 0

    public static func run(reason: String, embed!: Bool = false): Unit {
        synchronized(qmdMaintenanceLock) {
            if (!qmdConfigured()) {
                return
            }
            try {
                let _ = qmdEnsureManagedCollections()
                let (updateEc, _updateStdout, updateErr) = qmdRunUpdate()
                if (updateEc == 0) {
                    lastUpdateAtMs = DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000
                } else if (!updateErr.trimAscii().isEmpty()) {
                    LogUtils.error("QMD ${reason} update failed: ${updateErr.trimAscii()}")
                }
                if (embed) {
                    let (embedEc, _embedStdout, embedErr) = qmdRun(["embed"], CliConfig.qmdUpdateEmbedTimeoutMs)
                    if (embedEc == 0) {
                        lastEmbedAtMs = DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000
                    } else if (!embedErr.trimAscii().isEmpty()) {
                        LogUtils.error("QMD ${reason} embed failed: ${embedErr.trimAscii()}")
                    }
                }
            } catch (e: Exception) {
                LogUtils.error("QMD ${reason} maintenance failed: ${e.message}")
            }
        }
    }

    public static func startIfNeeded(): Unit {
        synchronized(qmdMaintenanceLock) {
            if (!qmdConfigured()) {
                return
            }
            if (let Some(_) <- maintenanceFuture) {
                return
            }
            maintenanceFuture = Some(spawn {
                if (CliConfig.qmdUpdateOnBoot) {
                    QmdMaintenanceRuntime.run("boot", embed: CliConfig.qmdUpdateWaitForBootSync)
                }
                var sleepMs: Int64 = 60000
                if (CliConfig.qmdUpdateIntervalMs > 0) {
                    sleepMs = CliConfig.qmdUpdateIntervalMs
                }
                if (CliConfig.qmdUpdateEmbedIntervalMs > 0 && CliConfig.qmdUpdateEmbedIntervalMs < sleepMs) {
                    sleepMs = CliConfig.qmdUpdateEmbedIntervalMs
                }
                sleepMs = max(1000, sleepMs)
                while (!Thread.currentThread.hasPendingCancellation) {
                    sleep(Duration.millisecond * sleepMs)
                    let nowMs = DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000
                    if (
                        CliConfig.qmdUpdateIntervalMs > 0 &&
                        (lastUpdateAtMs <= 0 || nowMs - lastUpdateAtMs >= CliConfig.qmdUpdateIntervalMs)
                    ) {
                        QmdMaintenanceRuntime.run("interval", embed: false)
                    }
                    if (
                        CliConfig.qmdUpdateEmbedIntervalMs > 0 &&
                        (lastEmbedAtMs <= 0 || nowMs - lastEmbedAtMs >= CliConfig.qmdUpdateEmbedIntervalMs)
                    ) {
                        QmdMaintenanceRuntime.run("embed-interval", embed: true)
                    }
                }
            })
        }
    }

    public static func stop(): Unit {
        synchronized(qmdMaintenanceLock) {
            if (let Some(future) <- maintenanceFuture) {
                future.cancel()
            }
            maintenanceFuture = None
        }
    }
}

public class MemoryProviderRegistry {
    private static var searchManagers = HashMap<String, MemorySearchManager>()
    private static var activeSearchBackendId = "local"
    private static var activeOrchestrationBackendId = "local"

    public static func runQmdMaintenanceCycle(reason: String, embed!: Bool = false): Unit {
        if (activeSearchBackendId != "qmd") {
            return
        }
        QmdMaintenanceRuntime.run(reason, embed: embed)
    }

    private static func startQmdMaintenanceIfNeeded(): Unit {
        if (activeSearchBackendId != "qmd") {
            return
        }
        QmdMaintenanceRuntime.startIfNeeded()
    }

    private static func stopQmdMaintenance(): Unit {
        QmdMaintenanceRuntime.stop()
    }

    private static func buildBackendConfig(provider: MemoryProvider): MemoryBackendConfig {
        MemoryBackendConfig(
            provider.providerId(),
            provider.backendId(),
            provider.searchEnabled(),
            provider.manualReindexSupported(),
            provider.indexPath()
        )
    }

    public static func register(provider: MemoryProvider): Unit {
        MemoryBackendAdapterRegistry.registerSearch(provider)
    }

    public static func registerOrchestration(backend: MemoryOrchestrationBackend, backendId!: String = ""): Unit {
        MemoryBackendAdapterRegistry.registerOrchestration(backend, backendId: backendId)
    }

    public static func activate(providerId: String, startMaintenance!: Bool = true): Bool {
        let pid = providerId.trimAscii()
        if (pid.isEmpty()) {
            return false
        }
        let (providerOpt, _selectionMode) = MemoryBackendAdapterRegistry.resolveSearchProviderSelection(pid)
        if (let None <- providerOpt) {
            return false
        }
        activeSearchBackendId = providerOpt.getOrThrow().providerId().trimAscii()
        if (activeSearchBackendId == "qmd" && startMaintenance) {
            startQmdMaintenanceIfNeeded()
        } else {
            stopQmdMaintenance()
        }
        true
    }

    public static func activeProviderName(): String {
        activeSearchBackendId
    }

    public static func registeredProviderIds(): Array<String> {
        MemoryBackendAdapterRegistry.registeredSearchProviderIds()
    }

    public static func registeredBackendConfigs(): Array<MemoryBackendConfig> {
        MemoryBackendAdapterRegistry.registeredSearchBackendConfigs()
    }

    public static func registeredOrchestrationBackendIds(): Array<String> {
        MemoryBackendAdapterRegistry.registeredOrchestrationBackendIds()
    }

    public static func currentOrchestrationBackendId(): String {
        activeOrchestrationBackendId
    }

    public static func currentSearchBackend(): MemoryProvider {
        match (MemoryBackendAdapterRegistry.resolveSearchProvider(activeSearchBackendId)) {
            case Some(provider) => provider
            case None =>
                let fallback = LocalMemoryProvider()
                MemoryBackendAdapterRegistry.registerSearch(fallback)
                activeSearchBackendId = "local"
                fallback
        }
    }

    public static func currentOrchestrationBackend(): MemoryOrchestrationBackend {
        match (MemoryBackendAdapterRegistry.resolveOrchestrationBackend(activeOrchestrationBackendId)) {
            case Some(backend) => backend
            case None =>
                let fallback = LocalMemoryOrchestrationBackend()
                MemoryBackendAdapterRegistry.registerOrchestration(fallback, backendId: "local")
                activeOrchestrationBackendId = "local"
                fallback
        }
    }

    public static func resolveMemoryBackendConfig(): MemoryBackendConfig {
        buildBackendConfig(currentSearchBackend())
    }

    public static func resolveMemoryBackendConfigSelection(
        providerOrBackendId: String
    ): Option<MemoryBackendConfig> {
        let (providerOpt, _selectionMode) = MemoryBackendAdapterRegistry.resolveSearchProviderSelection(
            providerOrBackendId
        )
        match (providerOpt) {
            case Some(provider) => Some(buildBackendConfig(provider))
            case None => None
        }
    }

    public static func resolveSearchBackendSelection(providerOrBackendId: String): Option<MemoryProvider> {
        let (providerOpt, _selectionMode) = MemoryBackendAdapterRegistry.resolveSearchProviderSelection(
            providerOrBackendId
        )
        providerOpt
    }

    private static func getMemorySearchManagerForProvider(provider: MemoryProvider): MemorySearchManagerResult {
        let providerId = provider.providerId()
        if (!provider.searchEnabled()) {
            return MemorySearchManagerResult(
                error: "Memory backend '${provider.backendId()}' does not support search."
            )
        }
        match (searchManagers.get(providerId)) {
            case Some(manager) =>
                MemorySearchManagerResult(manager: Some(manager))
            case None =>
                let manager = MemorySearchManager(provider, buildBackendConfig(provider))
                searchManagers[providerId] = manager
                MemorySearchManagerResult(manager: Some(manager))
        }
    }

    public static func getMemorySearchManager(): MemorySearchManagerResult {
        getMemorySearchManagerForProvider(currentSearchBackend())
    }

    public static func getMemorySearchManagerForSelection(providerOrBackendId: String): MemorySearchManagerResult {
        match (resolveSearchBackendSelection(providerOrBackendId)) {
            case Some(provider) => getMemorySearchManagerForProvider(provider)
            case None =>
                MemorySearchManagerResult(
                    error: "Memory backend '${providerOrBackendId.trimAscii()}' could not be resolved."
                )
        }
    }

    /**
     * Arm the active search backend manager without kicking off maintenance or
     * forcing qmd collection update/embed work. This mirrors the upstream startup
     * behavior: startup verifies that the configured memory backend can be
     * resolved, while heavy indexing remains on-demand.
     */
    public static func armActiveSearchManager(): MemorySearchManagerResult {
        getMemorySearchManager()
    }

    public static func closeAllMemorySearchManagers(): Unit {
        for ((_providerId, manager) in searchManagers) {
            manager.close()
        }
        searchManagers = HashMap<String, MemorySearchManager>()
        stopQmdMaintenance()
    }

    public static func startActiveMaintenance(): Unit {
        if (activeSearchBackendId == "qmd") {
            startQmdMaintenanceIfNeeded()
        }
    }

    public static func stopActiveMaintenance(): Unit {
        stopQmdMaintenance()
    }
}
