package metis.core.memory

import magic.jsonable.*
import std.collection.HashSet
import stdx.encoding.json.{JsonObject, JsonString}

public interface MemoryPromptSectionBuilder {
    func build(availableTools: HashSet<String>, citationsMode: String): Array<String>
}

public class MemoryFlushPlan {
    public let softThresholdTokens: Int64
    public let forceFlushTranscriptBytes: Int64
    public let reserveTokensFloor: Int64
    public let prompt: String
    public let systemPrompt: String
    public let relativePath: String

    public init(
        softThresholdTokens: Int64,
        forceFlushTranscriptBytes: Int64,
        reserveTokensFloor: Int64,
        prompt: String,
        systemPrompt: String,
        relativePath: String
    ) {
        this.softThresholdTokens = softThresholdTokens
        this.forceFlushTranscriptBytes = forceFlushTranscriptBytes
        this.reserveTokensFloor = reserveTokensFloor
        this.prompt = prompt
        this.systemPrompt = systemPrompt
        this.relativePath = relativePath
    }

    public func toJsonObject(): JsonObject {
        let obj = JsonObject()
        obj.put("softThresholdTokens", softThresholdTokens.toJsonValue())
        obj.put("forceFlushTranscriptBytes", forceFlushTranscriptBytes.toJsonValue())
        obj.put("reserveTokensFloor", reserveTokensFloor.toJsonValue())
        obj.put("prompt", JsonString(prompt))
        obj.put("systemPrompt", JsonString(systemPrompt))
        obj.put("relativePath", JsonString(relativePath))
        obj
    }
}

public interface MemoryFlushPlanResolver {
    func resolve(nowMs: Int64): Option<MemoryFlushPlan>
}

public interface MemoryPluginRuntime {
    func getMemorySearchManager(agentId: String, purpose: String): MemorySearchManagerResult
    func resolveMemoryBackendConfig(agentId: String): Option<MemoryBackendConfig>
    func closeAllMemorySearchManagers(): Unit
}

private class BuiltinMemoryPromptSectionBuilder <: MemoryPromptSectionBuilder {
    public func build(availableTools: HashSet<String>, citationsMode: String): Array<String> {
        let _ = availableTools
        let _ = citationsMode
        Array<String>()
    }
}

private class BuiltinMemoryFlushPlanResolver <: MemoryFlushPlanResolver {
    public func resolve(nowMs: Int64): Option<MemoryFlushPlan> {
        let _ = nowMs
        None<MemoryFlushPlan>
    }
}

private class BuiltinMemoryPluginRuntime <: MemoryPluginRuntime {
    public func getMemorySearchManager(agentId: String, purpose: String): MemorySearchManagerResult {
        let resolved = MemoryRuntimeRegistry.resolveBackendConfig(agentId: agentId, purpose: purpose)
        if (!resolved.searchEnabled || resolved.providerId.trimAscii().isEmpty()) {
            return MemorySearchManagerResult(error: "memory search disabled")
        }
        if (resolved.configScope == "global") {
            return MemoryProviderRegistry.getMemorySearchManager()
        }
        MemoryProviderRegistry.getMemorySearchManagerForSelection(resolved.providerId)
    }

    public func resolveMemoryBackendConfig(agentId: String): Option<MemoryBackendConfig> {
        Some(MemoryRuntimeRegistry.resolveBackendConfig(agentId: agentId, purpose: "default").toBackendConfig())
    }

    public func closeAllMemorySearchManagers(): Unit {
        MemoryProviderRegistry.closeAllMemorySearchManagers()
    }
}

private var memoryPromptSectionBuilder: Option<MemoryPromptSectionBuilder> = None
private var memoryFlushPlanResolver: Option<MemoryFlushPlanResolver> = None
private var memoryPluginRuntime: Option<MemoryPluginRuntime> = None

public func registerMemoryPromptSection(builder: MemoryPromptSectionBuilder): Unit {
    memoryPromptSectionBuilder = Some(builder)
}

public func getMemoryPromptSectionBuilder(): Option<MemoryPromptSectionBuilder> {
    memoryPromptSectionBuilder
}

public func buildMemoryPromptSection(
    availableTools: HashSet<String>,
    citationsMode!: String = ""
): Array<String> {
    match (memoryPromptSectionBuilder) {
        case Some(builder) => builder.build(availableTools, citationsMode)
        case None => Array<String>()
    }
}

public func buildMemoryPromptSectionForToolNames(
    toolNames: Array<String>,
    citationsMode!: String = ""
): Array<String> {
    let availableTools = HashSet<String>()
    for (toolName in toolNames) {
        let normalized = toolName.trimAscii()
        if (!normalized.isEmpty()) {
            availableTools.add(normalized)
        }
    }
    buildMemoryPromptSection(availableTools, citationsMode: citationsMode)
}

public func registerMemoryFlushPlanResolver(resolver: MemoryFlushPlanResolver): Unit {
    memoryFlushPlanResolver = Some(resolver)
}

public func getMemoryFlushPlanResolver(): Option<MemoryFlushPlanResolver> {
    memoryFlushPlanResolver
}

public func resolveMemoryFlushPlan(nowMs!: Int64 = 0): Option<MemoryFlushPlan> {
    match (memoryFlushPlanResolver) {
        case Some(resolver) => resolver.resolve(nowMs)
        case None => None<MemoryFlushPlan>
    }
}

public func registerMemoryRuntime(runtime: MemoryPluginRuntime): Unit {
    memoryPluginRuntime = Some(runtime)
}

public func getMemoryRuntime(): Option<MemoryPluginRuntime> {
    memoryPluginRuntime
}

public func hasMemoryRuntime(): Bool {
    memoryPluginRuntime.isSome()
}

public func restoreMemoryPluginState(
    promptBuilder!: Option<MemoryPromptSectionBuilder> = None,
    flushPlanResolver!: Option<MemoryFlushPlanResolver> = None,
    runtime!: Option<MemoryPluginRuntime> = None
): Unit {
    memoryPromptSectionBuilder = promptBuilder
    memoryFlushPlanResolver = flushPlanResolver
    memoryPluginRuntime = runtime
}

public func clearMemoryPluginState(): Unit {
    memoryPromptSectionBuilder = None
    memoryFlushPlanResolver = None
    memoryPluginRuntime = None
}

public func initializeBuiltinMemoryPluginState(): Unit {
    if (memoryPromptSectionBuilder.isNone()) {
        registerMemoryPromptSection(BuiltinMemoryPromptSectionBuilder())
    }
    if (memoryFlushPlanResolver.isNone()) {
        registerMemoryFlushPlanResolver(BuiltinMemoryFlushPlanResolver())
    }
    if (memoryPluginRuntime.isNone()) {
        registerMemoryRuntime(BuiltinMemoryPluginRuntime())
    }
}
