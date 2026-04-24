package metis.core.memory

import magic.jsonable.*
import std.fs.Path
import stdx.encoding.json.{JsonObject, JsonString, JsonValue}

/**
 * Legacy-style memory state surface.
 *
 * This module owns status, repair, and index-maintenance entrypoints so the
 * rest of the codebase no longer needs to reach directly into the low-level
 * manager for stateful operations.
 */
public class MemoryStateRegistry {
    private static func memoryStateJsonString(obj: JsonObject, key: String): String {
        match (obj.get(key)) {
            case Some(v) =>
                try { v.asString().getValue().trimAscii() } catch (_: Exception) { "" }
            case None => ""
        }
    }

    private static func memoryStateJsonBool(obj: JsonObject, key: String): Bool {
        match (obj.get(key)) {
            case Some(v) =>
                try { v.asBool().getValue() } catch (_: Exception) { false }
            case None => false
        }
    }

    private static func decorateStatusJson(raw: String, deep: Bool, agentId: String, purpose: String): String {
        let _ = deep
        let resolved = MemoryRuntime.resolveResolvedBackendConfig(agentId: agentId, purpose: purpose)
        match (JsonValue.fromStr(raw)) {
            case obj: JsonObject =>
                obj.put("provider", JsonString(resolved.providerId))
                obj.put("backend", JsonString(resolved.backend))
                obj.put("resolvedBackendConfig", resolved.toJsonObject())
                obj.put(
                    "backendSelection",
                    MemoryRuntimeRegistry.backendSelectionSummary(
                        agentId: agentId,
                        purpose: purpose
                    )
                )
                obj.put(
                    "agentScopedResolve",
                    MemoryRuntimeRegistry.agentScopedResolveSummary(
                        agentId: agentId,
                        purpose: purpose
                    )
                )
                obj.put(
                    "activeMemoryPlugin",
                    MemoryRuntimeRegistry.activeMemoryPluginSummary(
                        agentId: agentId,
                        purpose: purpose
                    )
                )
                obj.put("availableMemoryPlugins", MemoryRuntimeRegistry.registeredMemoryPluginSummaries())
                obj.put(
                    "activeSearchBackend",
                    MemoryRuntimeRegistry.activeSearchBackendSummary(
                        agentId: agentId,
                        purpose: purpose
                    )
                )
                obj.put("availableBackends", MemoryRuntimeRegistry.registeredBackendSummaries())
                obj.put("availableSelectionTargets", MemoryRuntimeRegistry.registeredBackendSelectionTargets())
                obj.put(
                    "activeOrchestrationBackend",
                    MemoryRuntimeRegistry.activeOrchestrationBackendSummary(
                        agentId: agentId,
                        purpose: purpose
                    )
                )
                obj.put("availableOrchestrationBackends", MemoryRuntimeRegistry.registeredOrchestrationBackendSummaries())
                obj.toJsonString()
            case _ => raw
        }
    }

    private static func unavailableStatusJson(agentId: String, purpose: String): String {
        let obj = JsonObject()
        obj.put("disabled", true.toJsonValue())
        obj.put("status", JsonString("unavailable"))
        obj.put("error", JsonString(MemoryRuntimeRegistry.memoryPluginUnavailableError()))
        decorateStatusJson(obj.toJsonString(), false, agentId, purpose)
    }

    private static func unavailableActionResult(action: String): String {
        let normalized = action.trimAscii()
        let label = if (normalized.isEmpty()) { "memory action" } else { normalized }
        "${label}: ${MemoryRuntimeRegistry.memoryPluginUnavailableError()}"
    }

    private static func decoratePreviewStatusJson(
        raw: String,
        deep: Bool,
        requestedBackend: String,
        agentId: String,
        purpose: String
    ): String {
        let base = decorateStatusJson(raw, deep, agentId, purpose)
        let previewSelection = MemoryRuntimeRegistry.previewBackendSelectionSummary(
            requestedBackend,
            agentId: agentId,
            purpose: purpose
        )
        let previewAgentScoped = MemoryRuntimeRegistry.previewAgentScopedResolveSummary(
            requestedBackend,
            agentId: agentId,
            purpose: purpose
        )
        match (JsonValue.fromStr(base)) {
            case obj: JsonObject =>
                obj.put("previewBackendSelection", previewSelection)
                obj.put("previewAgentScopedResolve", previewAgentScoped)
                match (previewSelection.get("resolvedBackendConfig")) {
                    case Some(v) => obj.put("previewResolvedBackendConfig", v)
                    case None => ()
                }
                obj.toJsonString()
            case _ => base
        }
    }

    public static func statusJson(deep!: Bool = false): String {
        statusJson(agentId: "", purpose: if (deep) { "status-deep" } else { "status" }, deep: deep)
    }

    public static func statusJson(
        agentId!: String = "",
        purpose!: String = "status",
        requestedBackend!: String = "",
        deep!: Bool = false
    ): String {
        let resolvedAgentId = agentId.trimAscii()
        let resolvedPurpose = if (purpose.trimAscii().isEmpty()) {
            if (deep) { "status-deep" } else { "status" }
        } else {
            purpose.trimAscii()
        }
        if (!MemoryRuntimeRegistry.memoryPluginAvailable()) {
            let unavailable = unavailableStatusJson(resolvedAgentId, resolvedPurpose)
            let normalizedRequested = requestedBackend.trimAscii()
            if (normalizedRequested.isEmpty()) {
                return unavailable
            }
            return decoratePreviewStatusJson(
                unavailable,
                deep,
                normalizedRequested,
                resolvedAgentId,
                resolvedPurpose
            )
        }
        let managerResult = MemoryRuntime.getMemorySearchManager(
            agentId: resolvedAgentId,
            purpose: resolvedPurpose
        )
        let raw = match (managerResult.manager) {
            case Some(manager) => manager.statusJson(deep: deep)
            case None => unavailableStatusJson(resolvedAgentId, resolvedPurpose)
        }
        let normalizedRequested = requestedBackend.trimAscii()
        if (normalizedRequested.isEmpty()) {
            return decorateStatusJson(raw, deep, resolvedAgentId, resolvedPurpose)
        }
        decoratePreviewStatusJson(raw, deep, normalizedRequested, resolvedAgentId, resolvedPurpose)
    }

    public static func statusText(deep!: Bool = false): String {
        statusText(agentId: "", purpose: if (deep) { "status-deep" } else { "status" }, deep: deep)
    }

    public static func statusText(
        agentId!: String = "",
        purpose!: String = "status",
        requestedBackend!: String = "",
        deep!: Bool = false
    ): String {
        let resolvedAgentId = agentId.trimAscii()
        let resolvedPurpose = if (purpose.trimAscii().isEmpty()) {
            if (deep) { "status-deep" } else { "status" }
        } else {
            purpose.trimAscii()
        }
        let resolved = MemoryRuntime.resolveResolvedBackendConfig(
            agentId: resolvedAgentId,
            purpose: resolvedPurpose
        )
        let selection = MemoryRuntimeRegistry.backendSelectionSummary(
            agentId: resolvedAgentId,
            purpose: resolvedPurpose
        )
        let activePlugin = MemoryRuntimeRegistry.activeMemoryPluginSummary(
            agentId: resolvedAgentId,
            purpose: resolvedPurpose
        )
        let scopedResolve = MemoryRuntimeRegistry.agentScopedResolveSummary(
            agentId: resolvedAgentId,
            purpose: resolvedPurpose
        )
        let baseText = if (MemoryRuntimeRegistry.memoryPluginAvailable()) {
            match (MemoryRuntime.getMemorySearchManager(
                agentId: resolvedAgentId,
                purpose: resolvedPurpose
            ).manager) {
                case Some(manager) => manager.statusText(deep: deep)
                case None => "Memory status: unavailable\nError: ${MemoryRuntimeRegistry.memoryPluginUnavailableError()}"
            }
        } else {
            "Memory status: unavailable\nError: ${MemoryRuntimeRegistry.memoryPluginUnavailableError()}"
        }
        let summary = baseText +
        "\nResolved config scope: ${resolved.configScope}" +
        "\nResolved purpose: ${resolved.purpose}" +
        "\nResolved agentId: ${resolved.agentId}" +
        "\nActive memory plugin: ${memoryStateJsonString(activePlugin, "pluginId")}" +
        "\nRequested backend: ${memoryStateJsonString(selection, "requestedBackend")}" +
        "\nSelection mode: ${memoryStateJsonString(selection, "selectionMode")}" +
        "\nResolved providerId: ${resolved.providerId}" +
        "\nResolved backend: ${resolved.backend}" +
        "\nScope source: ${memoryStateJsonString(scopedResolve, "scopeSource")}" +
        "\nInherits global: ${memoryStateJsonBool(scopedResolve, "inheritsGlobal")}"
        let normalizedRequested = requestedBackend.trimAscii()
        if (normalizedRequested.isEmpty()) {
            return summary
        }
        let previewSelection = MemoryRuntimeRegistry.previewBackendSelectionSummary(
            normalizedRequested,
            agentId: resolvedAgentId,
            purpose: resolvedPurpose
        )
        let previewScoped = MemoryRuntimeRegistry.previewAgentScopedResolveSummary(
            normalizedRequested,
            agentId: resolvedAgentId,
            purpose: resolvedPurpose
        )
        summary +
        "\nPreview requested backend: ${normalizedRequested}" +
        "\nPreview matched: ${memoryStateJsonBool(previewSelection, "matched")}" +
        "\nPreview selection mode: ${memoryStateJsonString(previewSelection, "selectionMode")}" +
        "\nPreview selected providerId: ${memoryStateJsonString(previewSelection, "selectedProviderId")}" +
        "\nPreview selected backend: ${memoryStateJsonString(previewSelection, "selectedBackend")}" +
        "\nPreview scope source: ${memoryStateJsonString(previewScoped, "scopeSource")}" +
        "\nPreview inherits global: ${memoryStateJsonBool(previewScoped, "inheritsGlobal")}"
    }

    public static func fixArtifacts(): String {
        fixArtifacts(agentId: "", purpose: "fix-artifacts")
    }

    public static func fixArtifacts(agentId!: String = "", purpose!: String = "fix-artifacts"): String {
        let resolvedAgentId = agentId.trimAscii()
        let resolvedPurpose = if (purpose.trimAscii().isEmpty()) { "fix-artifacts" } else { purpose.trimAscii() }
        if (!MemoryRuntimeRegistry.memoryPluginAvailable()) {
            return unavailableActionResult("fix artifacts")
        }
        let _resolved = MemoryRuntime.resolveResolvedBackendConfig(
            agentId: resolvedAgentId,
            purpose: resolvedPurpose
        )
        match (MemoryRuntime.getMemorySearchManager(
            agentId: resolvedAgentId,
            purpose: resolvedPurpose
        ).manager) {
            case Some(manager) => manager.fixArtifacts()
            case None => unavailableActionResult("fix artifacts")
        }
    }

    public static func writeIndexSnapshot(): String {
        writeIndexSnapshot(agentId: "", purpose: "write-index-snapshot")
    }

    public static func writeIndexSnapshot(
        agentId!: String = "",
        purpose!: String = "write-index-snapshot"
    ): String {
        let resolvedAgentId = agentId.trimAscii()
        let resolvedPurpose = if (purpose.trimAscii().isEmpty()) { "write-index-snapshot" } else { purpose.trimAscii() }
        if (!MemoryRuntimeRegistry.memoryPluginAvailable()) {
            return unavailableActionResult("write index snapshot")
        }
        let _resolved = MemoryRuntime.resolveResolvedBackendConfig(
            agentId: resolvedAgentId,
            purpose: resolvedPurpose
        )
        match (MemoryRuntime.getMemorySearchManager(
            agentId: resolvedAgentId,
            purpose: resolvedPurpose
        ).manager) {
            case Some(manager) => manager.writeIndexSnapshot()
            case None => unavailableActionResult("write index snapshot")
        }
    }

    public static func forceReindex(): String {
        forceReindex(agentId: "", purpose: "force-reindex")
    }

    public static func forceReindex(agentId!: String = "", purpose!: String = "force-reindex"): String {
        let resolvedAgentId = agentId.trimAscii()
        let resolvedPurpose = if (purpose.trimAscii().isEmpty()) { "force-reindex" } else { purpose.trimAscii() }
        if (!MemoryRuntimeRegistry.memoryPluginAvailable()) {
            return unavailableActionResult("force reindex")
        }
        let _resolved = MemoryRuntime.resolveResolvedBackendConfig(
            agentId: resolvedAgentId,
            purpose: resolvedPurpose
        )
        match (MemoryRuntime.getMemorySearchManager(
            agentId: resolvedAgentId,
            purpose: resolvedPurpose
        ).manager) {
            case Some(manager) => manager.forceReindex()
            case None => unavailableActionResult("force reindex")
        }
    }

    public static func indexStorePath(): Path {
        MemoryPaths.indexStorePath()
    }

    public static func sqliteStorePath(): Path {
        MemoryPaths.sqliteStorePath()
    }

    public static func shortTermRecallPath(): Path {
        MemoryPaths.shortTermRecallPath()
    }

    public static func promotedAuditPath(): Path {
        MemoryPaths.promotedAuditPath()
    }

    public static func durableMemoryPath(): Path {
        MemoryPaths.durableMemoryPath()
    }

    public static func dreamsDirPath(): Path {
        MemoryPaths.dreamsDirPath()
    }

    public static func dreamsMarkdownPath(): Path {
        MemoryPaths.dreamsMarkdownPath()
    }

    public static func ensureWorkspaceMemoryDir(): String {
        MemoryPaths.ensureWorkspaceMemoryDir()
    }
}
