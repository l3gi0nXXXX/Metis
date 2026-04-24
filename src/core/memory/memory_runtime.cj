package metis.core.memory

import std.fs.Path

/**
 * Legacy-style memory runtime surface.
 *
 * Runtime actions such as recall, promotion, and dreaming orchestration should
 * flow through this module instead of depending on the low-level manager
 * directly.
 */
public class MemoryRuntime {
    public static let DREAMING_CRON_NAME = MemoryPaths.DREAMING_CRON_NAME
    public static let DREAMING_LIGHT_CRON_NAME = MemoryPaths.DREAMING_LIGHT_CRON_NAME
    public static let DREAMING_REM_CRON_NAME = MemoryPaths.DREAMING_REM_CRON_NAME
    public static let DREAMING_SYSTEM_EVENT = MemoryPaths.DREAMING_SYSTEM_EVENT
    public static let DREAMING_LIGHT_SYSTEM_EVENT = MemoryPaths.DREAMING_LIGHT_SYSTEM_EVENT
    public static let DREAMING_REM_SYSTEM_EVENT = MemoryPaths.DREAMING_REM_SYSTEM_EVENT

    private static func unavailableOrchestrationResult(action: String): String {
        let normalized = action.trimAscii()
        let label = if (normalized.isEmpty()) { "memory orchestration" } else { normalized }
        "${label}: ${MemoryRuntimeRegistry.memoryPluginUnavailableError()}"
    }

    private static func ensureMemoryPluginRuntime(): Option<MemoryPluginRuntime> {
        if (!MemoryRuntimeRegistry.memoryPluginAvailable()) {
            return None<MemoryPluginRuntime>
        }
        let activePluginId = MemoryRuntimeRegistry.activeMemoryPluginId()
        if (activePluginId == "memory-core" && getMemoryRuntime().isNone()) {
            initializeBuiltinMemoryPluginState()
        }
        getMemoryRuntime()
    }

    public static func resolveResolvedBackendConfig(agentId!: String = "", purpose!: String = "default"): ResolvedMemoryBackendConfig {
        MemoryRuntimeRegistry.resolveBackendConfig(agentId: agentId, purpose: purpose)
    }

    public static func resolveMemoryBackendConfig(agentId!: String = "", purpose!: String = "default"): MemoryBackendConfig {
        let resolvedAgentId = agentId.trimAscii()
        let _ = purpose
        match (ensureMemoryPluginRuntime()) {
            case Some(runtime) =>
                match (runtime.resolveMemoryBackendConfig(resolvedAgentId)) {
                    case Some(cfg) => cfg
                    case None => MemoryRuntimeRegistry.resolveBackendConfig(agentId: agentId, purpose: purpose).toBackendConfig()
                }
            case None => MemoryRuntimeRegistry.resolveBackendConfig(agentId: agentId, purpose: purpose).toBackendConfig()
        }
    }

    public static func getMemorySearchManager(agentId!: String = "", purpose!: String = "default"): MemorySearchManagerResult {
        let resolvedAgentId = agentId.trimAscii()
        let resolvedPurpose = if (purpose.trimAscii().isEmpty()) { "default" } else { purpose.trimAscii() }
        match (ensureMemoryPluginRuntime()) {
            case Some(runtime) => runtime.getMemorySearchManager(resolvedAgentId, resolvedPurpose)
            case None => MemoryRuntimeRegistry.getActiveSearchManager(agentId: agentId, purpose: purpose)
        }
    }

    public static func armSearchBackend(agentId!: String = "", purpose!: String = "startup"): MemorySearchManagerResult {
        MemoryRuntimeRegistry.armActiveSearchManager(agentId: agentId, purpose: purpose)
    }

    public static func closeAllMemorySearchManagers(): Unit {
        match (ensureMemoryPluginRuntime()) {
            case Some(runtime) => runtime.closeAllMemorySearchManagers()
            case None => MemoryRuntimeRegistry.closeActiveSearchManagers()
        }
    }

    public static func startActiveMaintenance(): Unit {
        MemoryRuntimeRegistry.startActiveMaintenance()
    }

    public static func stopActiveMaintenance(): Unit {
        MemoryRuntimeRegistry.stopActiveMaintenance()
    }

    public static func searchEnabled(): Bool {
        searchEnabled(agentId: "", purpose: "default")
    }

    public static func searchEnabled(agentId!: String = "", purpose!: String = "default"): Bool {
        resolveMemoryBackendConfig(agentId: agentId, purpose: purpose).searchEnabled
    }

    public static func indexPath(): String {
        indexPath(agentId: "", purpose: "default")
    }

    public static func indexPath(agentId!: String = "", purpose!: String = "default"): String {
        resolveMemoryBackendConfig(agentId: agentId, purpose: purpose).indexPath
    }

    public static func resolveMemoryFiles(): Array<Path> {
        resolveMemoryFiles(agentId: "", purpose: "resolve-files")
    }

    public static func resolveMemoryFiles(agentId!: String = "", purpose!: String = "resolve-files"): Array<Path> {
        match (getMemorySearchManager(agentId: agentId, purpose: purpose).manager) {
            case Some(manager) => manager.resolveMemoryFiles()
            case None => Array<Path>()
        }
    }

    public static func searchRows(query: String, limit: Int64): Array<LocalMemorySearchRow> {
        searchRows(query, limit, sessionKey: None, agentId: "", purpose: "search")
    }

    public static func searchRows(
        query: String,
        limit: Int64,
        sessionKey!: Option<String>,
        agentId!: String = "",
        purpose!: String = "search"
    ): Array<LocalMemorySearchRow> {
        match (getMemorySearchManager(agentId: agentId, purpose: purpose).manager) {
            case Some(manager) => manager.searchRows(query, limit, sessionKey: sessionKey)
            case None => Array<LocalMemorySearchRow>()
        }
    }

    public static func recordShortTermRecall(query: String, rows: Array<LocalMemoryRecallResult>): Unit {
        recordShortTermRecall(query, rows, agentId: "", purpose: "record-recall")
    }

    public static func recordShortTermRecall(
        query: String,
        rows: Array<LocalMemoryRecallResult>,
        agentId!: String = "",
        purpose!: String = "record-recall"
    ): Unit {
        match (getMemorySearchManager(agentId: agentId, purpose: purpose).manager) {
            case Some(manager) => manager.recordShortTermRecall(query, rows)
            case None => ()
        }
    }

    public static func previewPromote(
        limit!: Int64 = 8,
        includePromoted!: Bool = false,
        minScore!: Float64 = 0.0,
        minRecallCount!: Int64 = 0,
        minUniqueQueries!: Int64 = 0,
        agentId!: String = "",
        purpose!: String = "promote-preview"
    ): String {
        if (!MemoryRuntimeRegistry.memoryPluginAvailable()) {
            return unavailableOrchestrationResult("preview promote")
        }
        MemoryRuntimeRegistry.activeOrchestrationBackend(
            agentId: agentId,
            purpose: purpose
        ).previewPromote(
            limit: limit,
            includePromoted: includePromoted,
            minScore: minScore,
            minRecallCount: minRecallCount,
            minUniqueQueries: minUniqueQueries
        )
    }

    public static func previewPromoteJson(
        limit!: Int64 = 8,
        includePromoted!: Bool = false,
        minScore!: Float64 = 0.0,
        minRecallCount!: Int64 = 0,
        minUniqueQueries!: Int64 = 0,
        agentId!: String = "",
        purpose!: String = "promote-preview-json"
    ): String {
        if (!MemoryRuntimeRegistry.memoryPluginAvailable()) {
            return unavailableOrchestrationResult("preview promote json")
        }
        MemoryRuntimeRegistry.activeOrchestrationBackend(
            agentId: agentId,
            purpose: purpose
        ).previewPromoteJson(
            limit: limit,
            includePromoted: includePromoted,
            minScore: minScore,
            minRecallCount: minRecallCount,
            minUniqueQueries: minUniqueQueries
        )
    }

    public static func explainPromote(
        selector: String,
        json!: Bool = false,
        limit!: Int64 = 12,
        includePromoted!: Bool = false,
        minScore!: Float64 = 0.0,
        minRecallCount!: Int64 = 0,
        minUniqueQueries!: Int64 = 0,
        agentId!: String = "",
        purpose!: String = "promote-explain"
    ): String {
        if (!MemoryRuntimeRegistry.memoryPluginAvailable()) {
            return unavailableOrchestrationResult("explain promote")
        }
        MemoryRuntimeRegistry.activeOrchestrationBackend(
            agentId: agentId,
            purpose: purpose
        ).explainPromote(
            selector,
            json: json,
            limit: limit,
            includePromoted: includePromoted,
            minScore: minScore,
            minRecallCount: minRecallCount,
            minUniqueQueries: minUniqueQueries
        )
    }

    public static func applyPromote(
        limit!: Int64 = 8,
        includePromoted!: Bool = false,
        minScore!: Float64 = 0.0,
        minRecallCount!: Int64 = 0,
        minUniqueQueries!: Int64 = 0,
        agentId!: String = "",
        purpose!: String = "promote-apply"
    ): String {
        if (!MemoryRuntimeRegistry.memoryPluginAvailable()) {
            return unavailableOrchestrationResult("apply promote")
        }
        MemoryRuntimeRegistry.activeOrchestrationBackend(
            agentId: agentId,
            purpose: purpose
        ).applyPromote(
            limit: limit,
            includePromoted: includePromoted,
            minScore: minScore,
            minRecallCount: minRecallCount,
            minUniqueQueries: minUniqueQueries
        )
    }

    public static func previewRemHarness(
        json!: Bool = false,
        includePromoted!: Bool = false,
        agentId!: String = "",
        purpose!: String = "rem-harness-preview"
    ): String {
        if (!MemoryRuntimeRegistry.memoryPluginAvailable()) {
            return unavailableOrchestrationResult("preview rem harness")
        }
        MemoryRuntimeRegistry.activeOrchestrationBackend(
            agentId: agentId,
            purpose: purpose
        ).previewRemHarness(json: json, includePromoted: includePromoted)
    }

    public static func applyRemHarness(
        includePromoted!: Bool = false,
        limit!: Int64 = 6,
        lookbackDays!: Int64 = 14,
        agentId!: String = "",
        purpose!: String = "rem-harness-apply"
    ): String {
        if (!MemoryRuntimeRegistry.memoryPluginAvailable()) {
            return unavailableOrchestrationResult("apply rem harness")
        }
        MemoryRuntimeRegistry.activeOrchestrationBackend(
            agentId: agentId,
            purpose: purpose
        ).applyRemHarness(
            includePromoted: includePromoted,
            limit: limit,
            lookbackDays: lookbackDays
        )
    }

    public static func applyLightDreaming(
        includePromoted!: Bool = false,
        limit!: Int64 = 6,
        lookbackDays!: Int64 = 14,
        agentId!: String = "",
        purpose!: String = "dreaming-light-apply"
    ): String {
        if (!MemoryRuntimeRegistry.memoryPluginAvailable()) {
            return unavailableOrchestrationResult("apply light dreaming")
        }
        MemoryRuntimeRegistry.activeOrchestrationBackend(
            agentId: agentId,
            purpose: purpose
        ).applyLightDreaming(
            includePromoted: includePromoted,
            limit: limit,
            lookbackDays: lookbackDays
        )
    }

    public static func applyDeepDreaming(
        includePromoted!: Bool = false,
        limit!: Int64 = 6,
        lookbackDays!: Int64 = 21,
        agentId!: String = "",
        purpose!: String = "dreaming-deep-apply"
    ): String {
        if (!MemoryRuntimeRegistry.memoryPluginAvailable()) {
            return unavailableOrchestrationResult("apply deep dreaming")
        }
        MemoryRuntimeRegistry.activeOrchestrationBackend(
            agentId: agentId,
            purpose: purpose
        ).applyDeepDreaming(
            includePromoted: includePromoted,
            limit: limit,
            lookbackDays: lookbackDays
        )
    }

    public static func applyDreamingSweep(
        includePromoted!: Bool = false,
        agentId!: String = "",
        purpose!: String = "dreaming-sweep-apply"
    ): String {
        if (!MemoryRuntimeRegistry.memoryPluginAvailable()) {
            return unavailableOrchestrationResult("apply dreaming sweep")
        }
        MemoryRuntimeRegistry.activeOrchestrationBackend(
            agentId: agentId,
            purpose: purpose
        ).applyDreamingSweep(includePromoted: includePromoted)
    }
}
