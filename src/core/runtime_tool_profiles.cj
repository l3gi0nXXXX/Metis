package metis.core

import std.collection.{ArrayList, HashMap}
import std.sync.Mutex
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

public class RuntimeToolPolicyReport {
    public var agentId: String = ""
    public var provider: String = ""
    public var policySource: String = "unrestricted"
    public var visibleTools: Array<String> = []
    public var deniedTools: Array<String> = []
    public var diagnostics: Array<String> = []
    public var elevatedExplanation: String = "tools.elevated is a global sender-based approval boundary; it is not a per-agent credential or auth-profile sharing rule."
    public init() {}
}

public class RuntimeToolInvocationDecision {
    public var allowed: Bool = true
    public var status: String = "allowed"
    public var reason: String = "allowed"
    public var toolName: String = ""
    public var policySource: String = "unrestricted"
    public init() {}
}

public class RuntimeSubagentBoundaryDecision {
    public var allowed: Bool = true
    public var reason: String = "allowed"
    public var blockedTool: String = ""
    public init() {}
}

public class RuntimeToolInvocationPolicyContext {
    public let root: JsonObject
    public let inventory: Array<String>
    public let agentId: String
    public let provider: String

    public init(root: JsonObject, inventory: Array<String>, agentId!: String = "", provider!: String = "") {
        this.root = root
        this.inventory = inventory
        this.agentId = agentId.trimAscii()
        this.provider = provider.trimAscii()
    }
}

private class RuntimeToolPolicyScope {
    public var source: String = ""
    public var allow: Array<String> = []
    public var alsoAllow: Array<String> = []
    public var deny: Array<String> = []
    public var profile: String = ""
    public init() {}
}

public func gatewayMainRuntimeRequiredToolNames(): Array<String> {
    [
        "weather",
        "listDirectory",
        "fileRead",
        "memory_search",
        "memory_get",
        "shellExecute",
        "update_plan",
        "sessions_list",
        "sessions_history",
        "sessions_send",
        "session_status"
    ]
}

public func gatewayMainRuntimeExtendedToolNames(): Array<String> {
    [
        "process",
        "gateway",
        "cron",
        "message",
        "sessions_spawn",
        "subagents"
    ]
}

public func runtimeToolNamesContain(toolNames: Array<String>, expected: String): Bool {
    let needle = expected.trimAscii().toAsciiLower()
    for (name in toolNames) {
        if (name.trimAscii().toAsciiLower() == needle) {
            return true
        }
    }
    false
}

public func runtimeToolNamesContainAll(toolNames: Array<String>, expectedNames: Array<String>): Bool {
    for (expected in expectedNames) {
        if (!runtimeToolNamesContain(toolNames, expected)) {
            return false
        }
    }
    true
}

public func missingRuntimeToolNames(toolNames: Array<String>, expectedNames: Array<String>): Array<String> {
    let missing = ArrayList<String>()
    for (expected in expectedNames) {
        if (!runtimeToolNamesContain(toolNames, expected)) {
            missing.add(expected)
        }
    }
    missing.toArray()
}

private func runtimeToolNormalizeName(raw: String): String {
    raw.trimAscii().toAsciiLower()
}

private func runtimeToolCanonicalNames(raw: String): Array<String> {
    let normalized = runtimeToolNormalizeName(raw)
    match (normalized) {
        case "exec" | "shell" | "shell-execute" | "shell_execute" => ["shellexecute"]
        case "fs" | "file" | "files" | "filesystem" => ["fileread", "listdirectory", "globsearch", "grepsearch"]
        case "memory" => ["memory_search", "memory_get"]
        case "sessions" | "subagent" => ["sessions_spawn", "sessions_batch_delegate", "subagents"]
        case _ => [normalized]
    }
}

private func runtimeToolJsonStringArray(obj: JsonObject, key: String): Array<String> {
    let out = ArrayList<String>()
    match (obj.get(key)) {
        case Some(value) =>
            try {
                let arr = value.asArray()
                for (i in 0..arr.size()) {
                    try {
                        let text = arr[i].asString().getValue().trimAscii()
                        if (!text.isEmpty()) {
                            out.add(text)
                        }
                    } catch (_: Exception) {
                        ()
                    }
                }
            } catch (_: Exception) {
                ()
            }
        case None => ()
    }
    out.toArray()
}

private func runtimeToolJsonObject(obj: JsonObject, key: String): Option<JsonObject> {
    match (obj.get(key)) {
        case Some(value) =>
            try { Some(value.asObject()) } catch (_: Exception) { None<JsonObject> }
        case None => None<JsonObject>
    }
}

private func runtimeToolJsonString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(value) =>
            try { value.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func runtimeToolPolicyScopeFromObject(obj: JsonObject, source: String): RuntimeToolPolicyScope {
    let scope = RuntimeToolPolicyScope()
    scope.source = source
    scope.allow = runtimeToolJsonStringArray(obj, "allow")
    scope.alsoAllow = runtimeToolJsonStringArray(obj, "alsoAllow")
    scope.deny = runtimeToolJsonStringArray(obj, "deny")
    scope.profile = runtimeToolJsonString(obj, "profile")
    scope
}

private func runtimeToolAddScope(scopes: ArrayList<RuntimeToolPolicyScope>, objOpt: Option<JsonObject>, source: String): Unit {
    match (objOpt) {
        case Some(obj) =>
            scopes.add(runtimeToolPolicyScopeFromObject(obj, source))
        case None => ()
    }
}

private func runtimeToolSandboxTools(objOpt: Option<JsonObject>): Option<JsonObject> {
    match (objOpt) {
        case Some(obj) =>
            match (runtimeToolJsonObject(obj, "sandbox")) {
                case Some(sandbox) => runtimeToolJsonObject(sandbox, "tools")
                case None => None<JsonObject>
            }
        case None => None<JsonObject>
    }
}

private func runtimeToolProviderBase(provider: String): String {
    let clean = provider.trimAscii().toAsciiLower()
    match (clean.indexOf("/")) {
        case Some(idx) => clean[0..idx]
        case None => clean
    }
}

private func runtimeToolAddProviderScopes(
    scopes: ArrayList<RuntimeToolPolicyScope>,
    toolsObjOpt: Option<JsonObject>,
    provider: String,
    sourcePrefix: String
): Unit {
    let cleanProvider = provider.trimAscii().toAsciiLower()
    if (cleanProvider.isEmpty()) {
        return
    }
    let baseProvider = runtimeToolProviderBase(cleanProvider)
    match (toolsObjOpt) {
        case Some(toolsObj) =>
            match (runtimeToolJsonObject(toolsObj, "byProvider")) {
                case Some(byProvider) =>
                    match (runtimeToolJsonObject(byProvider, baseProvider)) {
                        case Some(policy) => scopes.add(runtimeToolPolicyScopeFromObject(policy, "${sourcePrefix}.byProvider[${baseProvider}]"))
                        case None => ()
                    }
                    if (cleanProvider != baseProvider) {
                        match (runtimeToolJsonObject(byProvider, cleanProvider)) {
                            case Some(policy) => scopes.add(runtimeToolPolicyScopeFromObject(policy, "${sourcePrefix}.byProvider[${cleanProvider}]"))
                            case None => ()
                        }
                    }
                case None => ()
            }
        case None => ()
    }
}

private func runtimeToolAgentEntry(root: JsonObject, agentId: String): Option<JsonObject> {
    let wanted = runtimeToolNormalizeName(agentId)
    if (wanted.isEmpty()) {
        return None<JsonObject>
    }
    match (runtimeToolJsonObject(root, "agents")) {
        case Some(agents) =>
            match (agents.get("list")) {
                case Some(value) =>
                    try {
                        let list = value.asArray()
                        for (i in 0..list.size()) {
                            let entry = try { list[i].asObject() } catch (_: Exception) { continue }
                            if (runtimeToolNormalizeName(runtimeToolJsonString(entry, "id")) == wanted) {
                                return Some(entry)
                            }
                        }
                    } catch (_: Exception) {
                        ()
                    }
                case None => ()
            }
        case None => ()
    }
    None<JsonObject>
}

private func runtimeToolPolicyScopes(root: JsonObject, agentId: String, provider: String): ArrayList<RuntimeToolPolicyScope> {
    let scopes = ArrayList<RuntimeToolPolicyScope>()
    let rootTools = runtimeToolJsonObject(root, "tools")
    runtimeToolAddScope(scopes, rootTools, "tools")
    runtimeToolAddProviderScopes(scopes, rootTools, provider, "tools")
    let rootSandboxTools = runtimeToolSandboxTools(rootTools)
    runtimeToolAddScope(scopes, rootSandboxTools, "tools.sandbox.tools")
    runtimeToolAddProviderScopes(scopes, rootSandboxTools, provider, "tools.sandbox.tools")

    let gatewayTools = match (runtimeToolJsonObject(root, "gateway")) {
        case Some(gateway) => runtimeToolJsonObject(gateway, "tools")
        case None => None<JsonObject>
    }
    runtimeToolAddScope(scopes, gatewayTools, "gateway.tools")
    runtimeToolAddProviderScopes(scopes, gatewayTools, provider, "gateway.tools")
    let gatewaySandboxTools = runtimeToolSandboxTools(gatewayTools)
    runtimeToolAddScope(scopes, gatewaySandboxTools, "gateway.tools.sandbox.tools")
    runtimeToolAddProviderScopes(scopes, gatewaySandboxTools, provider, "gateway.tools.sandbox.tools")

    match (runtimeToolJsonObject(root, "agents")) {
        case Some(agents) =>
            let defaultsTools = match (runtimeToolJsonObject(agents, "defaults")) {
                case Some(defaults) => runtimeToolJsonObject(defaults, "tools")
                case None => None<JsonObject>
            }
            runtimeToolAddScope(scopes, defaultsTools, "agents.defaults.tools")
            runtimeToolAddProviderScopes(scopes, defaultsTools, provider, "agents.defaults.tools")
            let defaultsSandboxTools = runtimeToolSandboxTools(defaultsTools)
            runtimeToolAddScope(scopes, defaultsSandboxTools, "agents.defaults.tools.sandbox.tools")
            runtimeToolAddProviderScopes(scopes, defaultsSandboxTools, provider, "agents.defaults.tools.sandbox.tools")
        case None => ()
    }

    match (runtimeToolAgentEntry(root, agentId)) {
        case Some(entry) =>
            let agentTools = runtimeToolJsonObject(entry, "tools")
            runtimeToolAddScope(scopes, agentTools, "agents.list[${runtimeToolNormalizeName(agentId)}].tools")
            runtimeToolAddProviderScopes(scopes, agentTools, provider, "agents.list[${runtimeToolNormalizeName(agentId)}].tools")
            let agentSandboxTools = runtimeToolSandboxTools(agentTools)
            runtimeToolAddScope(scopes, agentSandboxTools, "agents.list[${runtimeToolNormalizeName(agentId)}].tools.sandbox.tools")
            runtimeToolAddProviderScopes(scopes, agentSandboxTools, provider, "agents.list[${runtimeToolNormalizeName(agentId)}].tools.sandbox.tools")
        case None => ()
    }
    match (runtimeToolJsonObject(root, "runtimeTurn")) {
        case Some(turn) =>
            let turnTools = runtimeToolJsonObject(turn, "tools")
            runtimeToolAddScope(scopes, turnTools, "runtimeTurn.tools")
            runtimeToolAddProviderScopes(scopes, turnTools, provider, "runtimeTurn.tools")
        case None => ()
    }
    scopes
}

private func runtimeToolInventorySet(inventory: Array<String>): HashMap<String, Bool> {
    let out = HashMap<String, Bool>()
    for (tool in inventory) {
        let normalized = runtimeToolNormalizeName(tool)
        if (!normalized.isEmpty()) {
            out[normalized] = true
        }
    }
    out
}

private func runtimeToolCanonicalSet(values: Array<String>, inventory: Array<String>): HashMap<String, Bool> {
    let out = HashMap<String, Bool>()
    let inventorySet = runtimeToolInventorySet(inventory)
    for (value in values) {
        for (canonical in runtimeToolCanonicalNames(value)) {
            if (canonical.isEmpty()) {
                continue
            }
            if (canonical == "*" || inventorySet.contains(canonical)) {
                out[canonical] = true
            }
        }
    }
    out
}

private func runtimeToolProfileSet(profile: String, inventory: Array<String>): HashMap<String, Bool> {
    let normalized = runtimeToolNormalizeName(profile)
    let names: Array<String> = match (normalized) {
        case "minimal" => ["fileread", "listdirectory", "memory_search", "memory_get", "weather"]
        case "coding" => ["fileread", "listdirectory", "globsearch", "grepsearch", "shellexecute", "update_plan", "memory_search", "memory_get"]
        case "messaging" => ["message", "sessions_list", "sessions_history", "sessions_send", "session_status", "weather"]
        case "full" => Array<String>() // Empty means all inventory for the full profile.
        case _ => Array<String>()
    }
    let out = HashMap<String, Bool>()
    if (normalized == "full" || normalized.isEmpty()) {
        return runtimeToolInventorySet(inventory)
    }
    for (name in names) {
        out[name] = true
    }
    out
}

private func runtimeToolIntersectAllowed(current: HashMap<String, Bool>, allowed: HashMap<String, Bool>): HashMap<String, Bool> {
    let out = HashMap<String, Bool>()
    for ((key, _) in current) {
        if (allowed.contains(key)) {
            out[key] = true
        }
    }
    out
}

private func runtimeToolArrayToSet(values: Array<String>, inventory: Array<String>): HashMap<String, Bool> {
    runtimeToolCanonicalSet(values, inventory)
}

private func runtimeToolSetContains(values: Array<String>, target: String, inventory!: Array<String> = []): Bool {
    let needles = runtimeToolCanonicalNames(target)
    for (value in values) {
        let normalized = runtimeToolNormalizeName(value)
        if (normalized == "*") {
            return true
        }
        for (candidate in runtimeToolCanonicalNames(value)) {
            for (needle in needles) {
                if (candidate == needle) {
                    return true
                }
            }
        }
    }
    false
}

private func runtimeToolAppendDiagnostic(diagnostics: ArrayList<String>, text: String): Unit {
    let clean = text.trimAscii()
    if (!clean.isEmpty()) {
        diagnostics.add(clean)
    }
}

private func runtimeToolAddPolicySource(sources: ArrayList<String>, source: String): Unit {
    let clean = source.trimAscii()
    if (clean.isEmpty()) {
        return
    }
    for (existing in sources) {
        if (existing == clean) {
            return
        }
    }
    sources.add(clean)
}

public func resolveRuntimeToolPolicyFromRoot(
    root: JsonObject,
    inventory: Array<String>,
    agentId!: String = "",
    provider!: String = ""
): RuntimeToolPolicyReport {
    let report = RuntimeToolPolicyReport()
    report.agentId = agentId.trimAscii()
    report.provider = provider.trimAscii()

    var current = runtimeToolInventorySet(inventory)
    let denied = HashMap<String, Bool>()
    var denyAll = false
    let diagnostics = ArrayList<String>()
    let sources = ArrayList<String>()
    let scopes = runtimeToolPolicyScopes(root, agentId, provider)

    for (scope in scopes) {
        let hasPolicy = scope.allow.size > 0 || scope.alsoAllow.size > 0 || scope.deny.size > 0 || !scope.profile.isEmpty()
        if (!hasPolicy) {
            continue
        }
        runtimeToolAddPolicySource(sources, scope.source)
        if (scope.allow.size > 0 && scope.alsoAllow.size > 0) {
            runtimeToolAppendDiagnostic(diagnostics, "${scope.source}: allow and alsoAllow cannot both be set in the same policy scope")
        }
        var scopeConstrainsTools = false
        var scopeAllowed = runtimeToolInventorySet(inventory)
        if (!scope.profile.isEmpty()) {
            scopeAllowed = runtimeToolProfileSet(scope.profile, inventory)
            scopeConstrainsTools = true
        }
        if (scope.allow.size > 0) {
            scopeAllowed = runtimeToolArrayToSet(scope.allow, inventory)
            scopeConstrainsTools = true
        }
        if (scope.alsoAllow.size > 0 && !scope.profile.isEmpty() && scope.allow.size == 0) {
            for ((name, _) in runtimeToolArrayToSet(scope.alsoAllow, inventory)) {
                if (!name.isEmpty() && name != "*") {
                    scopeAllowed[name] = true
                }
            }
        }
        if (scopeConstrainsTools) {
            current = runtimeToolIntersectAllowed(current, scopeAllowed)
        }
        for (name in scope.deny) {
            for (normalized in runtimeToolCanonicalNames(name)) {
                if (normalized.isEmpty()) {
                    continue
                }
                if (normalized == "*") {
                    denyAll = true
                    current.clear()
                    runtimeToolAppendDiagnostic(diagnostics, "${scope.source}: deny wins over allow/profile for all tools")
                    continue
                }
                if (runtimeToolSetContains(scope.allow, normalized, inventory: inventory) ||
                    runtimeToolSetContains(scope.alsoAllow, normalized, inventory: inventory) ||
                    (!scope.profile.isEmpty() && runtimeToolProfileSet(scope.profile, inventory).contains(normalized))) {
                    runtimeToolAppendDiagnostic(diagnostics, "${scope.source}: deny wins over allow/profile for ${name.trimAscii()}")
                }
                denied[normalized] = true
                current.remove(normalized)
            }
        }
    }

    let visible = ArrayList<String>()
    let restricted = ArrayList<String>()
    for (tool in inventory) {
        let normalized = runtimeToolNormalizeName(tool)
        if (!normalized.isEmpty() && current.contains(normalized) && !denied.contains(normalized) && !denyAll) {
            visible.add(tool)
        } else {
            restricted.add(tool)
        }
    }
    report.visibleTools = visible.toArray()
    report.deniedTools = restricted.toArray()
    report.diagnostics = diagnostics.toArray()
    report.policySource = if (sources.size == 0) { "unrestricted" } else { String.join(sources.toArray(), delimiter: " + ") }
    report
}

private let runtimeToolInvocationPolicyContextLock = Mutex()
private let runtimeToolInvocationPolicyContextByThread = HashMap<String, ArrayList<RuntimeToolInvocationPolicyContext>>()

private func runtimeToolInvocationPolicyThreadKey(): String {
    Thread.currentThread.name.trimAscii()
}

private func runtimeToolInvocationPolicyStack(threadKey: String): ArrayList<RuntimeToolInvocationPolicyContext> {
    match (runtimeToolInvocationPolicyContextByThread.get(threadKey)) {
        case Some(existing) => existing
        case None =>
            let created = ArrayList<RuntimeToolInvocationPolicyContext>()
            runtimeToolInvocationPolicyContextByThread[threadKey] = created
            created
    }
}

public func runtimeCurrentToolInvocationPolicyContext(): Option<RuntimeToolInvocationPolicyContext> {
    synchronized(runtimeToolInvocationPolicyContextLock) {
        match (runtimeToolInvocationPolicyContextByThread.get(runtimeToolInvocationPolicyThreadKey())) {
            case Some(stack) =>
                if (stack.size > 0) {
                    Some(stack[stack.size - 1])
                } else {
                    None<RuntimeToolInvocationPolicyContext>
                }
            case None => None<RuntimeToolInvocationPolicyContext>
        }
    }
}

public func runtimePushToolInvocationPolicyContext(context: RuntimeToolInvocationPolicyContext): Unit {
    synchronized(runtimeToolInvocationPolicyContextLock) {
        runtimeToolInvocationPolicyStack(runtimeToolInvocationPolicyThreadKey()).add(context)
    }
}

public func runtimePopToolInvocationPolicyContext(): Unit {
    synchronized(runtimeToolInvocationPolicyContextLock) {
        let threadKey = runtimeToolInvocationPolicyThreadKey()
        match (runtimeToolInvocationPolicyContextByThread.get(threadKey)) {
            case Some(stack) =>
                if (stack.size > 0) {
                    stack.remove(at: stack.size - 1)
                }
                if (stack.size == 0) {
                    runtimeToolInvocationPolicyContextByThread.remove(threadKey)
                }
            case None => ()
        }
    }
}

public func runtimeWithToolInvocationPolicyContext<T>(
    root: JsonObject,
    inventory: Array<String>,
    block: () -> T,
    agentId!: String = "",
    provider!: String = ""
): T {
    runtimePushToolInvocationPolicyContext(RuntimeToolInvocationPolicyContext(root, inventory, agentId: agentId, provider: provider))
    try {
        block()
    } finally {
        runtimePopToolInvocationPolicyContext()
    }
}

public func runtimeToolDiagnosticsContain(report: RuntimeToolPolicyReport, needle: String): Bool {
    let clean = needle.trimAscii().toAsciiLower()
    for (line in report.diagnostics) {
        if (line.toAsciiLower().contains(clean)) {
            return true
        }
    }
    false
}

private func runtimeToolStringArrayJson(values: Array<String>): JsonArray {
    let arr = JsonArray([])
    for (value in values) {
        arr.add(JsonString(value))
    }
    arr
}

public func runtimeToolPolicyReportToJson(report: RuntimeToolPolicyReport): JsonObject {
    let obj = JsonObject()
    obj.put("agentId", JsonString(report.agentId))
    obj.put("provider", JsonString(report.provider))
    obj.put("policySource", JsonString(report.policySource))
    obj.put("visibleTools", runtimeToolStringArrayJson(report.visibleTools))
    obj.put("deniedTools", runtimeToolStringArrayJson(report.deniedTools))
    obj.put("diagnostics", runtimeToolStringArrayJson(report.diagnostics))
    obj.put("elevated", JsonString(report.elevatedExplanation))
    return obj
}

public func runtimeToolInvocationAllowedFromRoot(
    root: JsonObject,
    toolName: String,
    inventory: Array<String>,
    agentId!: String = "",
    provider!: String = ""
): RuntimeToolInvocationDecision {
    let decision = RuntimeToolInvocationDecision()
    decision.toolName = toolName.trimAscii()
    let report = resolveRuntimeToolPolicyFromRoot(root, inventory, agentId: agentId, provider: provider)
    decision.policySource = report.policySource
    var knownTool = false
    var visibleTool = false
    for (canonical in runtimeToolCanonicalNames(toolName)) {
        if (runtimeToolNamesContain(inventory, canonical)) {
            knownTool = true
        }
        if (runtimeToolNamesContain(report.visibleTools, canonical)) {
            visibleTool = true
        }
    }
    if (!knownTool) {
        decision.allowed = false
        decision.status = "rejected"
        decision.reason = "unknown tool: ${toolName.trimAscii()}"
        return decision
    }
    if (!visibleTool) {
        decision.allowed = false
        decision.status = "rejected"
        decision.reason = "tool denied by policy: ${toolName.trimAscii()}"
        return decision
    }
    decision
}

public func runtimeSubagentBoundaryDecision(
    parentPolicy: RuntimeToolPolicyReport,
    requestedAgentId!: String = "",
    requireAgentId!: Bool = false,
    allowAgents!: Array<String> = [],
    requestedTools!: Array<String> = []
): RuntimeSubagentBoundaryDecision {
    let decision = RuntimeSubagentBoundaryDecision()
    let cleanAgentId = requestedAgentId.trimAscii()
    if (requireAgentId && cleanAgentId.isEmpty()) {
        decision.allowed = false
        decision.reason = "agent id required"
        return decision
    }
    if (allowAgents.size > 0 && !runtimeToolSetContains(allowAgents, cleanAgentId)) {
        decision.allowed = false
        decision.reason = "agent not allowed: ${cleanAgentId}"
        return decision
    }
    for (toolName in requestedTools) {
        if (!runtimeToolNamesContain(parentPolicy.visibleTools, toolName)) {
            decision.allowed = false
            decision.blockedTool = toolName.trimAscii()
            decision.reason = "parent tool policy denied requested subagent tool: ${toolName.trimAscii()}"
            return decision
        }
    }
    decision
}
