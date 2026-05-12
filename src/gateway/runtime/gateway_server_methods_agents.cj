package metis.gateway.runtime

import magic.jsonable.*

import metis.core.{gatewayMainRuntimeExtendedToolNames, gatewayMainRuntimeRequiredToolNames, missingRuntimeToolNames}
import metis.core.config.{CliConfig, CliSettingManager, MetisAgentScope, MetisConfigManager, MetisPaths, GatewayUserSettings}
import metis.core.memory.MemoryRuntimeRegistry
import metis.core.prompting.{MetisAgentWorkspaceBootstrapResult, ensureMetisAgentWorkspace}
import metis.core.skills.resolveAgentSkillVisibility
import metis.gateway.config.buildGatewayConfigFromUserSettings
import metis.gateway.core.{gatewayAuthorizedChatToolNames, gatewayCorePromptRuntimeCapabilities, gatewayDefaultChatRuntimeHasUnifiedCoreTools, gatewayDefaultChatToolNames, gatewayMainRuntimePromptTemplateId, gatewayMainRuntimePromptVarianceFields, gatewaySanitizeAgentId}
import metis.gateway.session.{GatewayIngressSource, GatewaySessionRequest, gatewayBuildSessionRpcParams, gatewayIngressSourceFromString, gatewayResolveSessionContext, gatewaySessionRequestFromRpcParams}

import std.collection.{ArrayList, HashMap}
import std.convert.Parsable
import std.fs.{Directory, File, Path, exists, remove}
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private func gatewayAgentRpcStringParam(request: GatewayRpcRequest, keys: Array<String>, defaultValue: String): String {
    for (key in keys) {
        match (request.params.get(key)) {
            case Some(v) =>
                try {
                    let value = v.asString().getValue().trimAscii()
                    if (!value.isEmpty()) {
                        return value
                    }
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
    }
    defaultValue
}

private func gatewayAgentJsonString(obj: JsonObject, key: String, defaultValue: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { defaultValue }
        case None => defaultValue
    }
}

private func gatewayAgentJsonBool(obj: JsonObject, key: String, defaultValue: Bool): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { defaultValue }
        case None => defaultValue
    }
}

private func gatewayAgentConfigRootClone(): JsonObject {
    MetisConfigManager.initializeIfMissing()
    match (MetisConfigManager.rawConfig()) {
        case Some(root) =>
            try {
                JsonValue.fromStr(root.toJsonString()).asObject()
            } catch (_e: Exception) {
                JsonObject()
            }
        case None => JsonObject()
    }
}

private func gatewayAgentConfigRootCloneReadOnly(): JsonObject {
    match (MetisConfigManager.rawConfig()) {
        case Some(root) =>
            try {
                JsonValue.fromStr(root.toJsonString()).asObject()
            } catch (_e: Exception) {
                JsonObject()
            }
        case None => JsonObject()
    }
}

private func gatewayAgentScopeRootFromRequest(request: GatewayRpcRequest): JsonObject {
    match (request.params.get("configRoot")) {
        case Some(v) =>
            try { return scopeCloneObjectForGateway(v.asObject()) } catch (_e: Exception) { () }
        case None => ()
    }
    gatewayAgentConfigRootCloneReadOnly()
}

private func scopeCloneObjectForGateway(root: JsonObject): JsonObject {
    try {
        JsonValue.fromStr(root.toJsonString()).asObject()
    } catch (_e: Exception) {
        JsonObject()
    }
}

private func gatewayAgentScopePathParam(request: GatewayRpcRequest, key: String, fallback: Path): Path {
    let raw = gatewayAgentRpcStringParam(request, [key], "")
    if (raw.trimAscii().isEmpty()) {
        return fallback
    }
    try { Path(raw.trimAscii()).normalize() } catch (_e: Exception) { Path(raw.trimAscii()) }
}

private func gatewayAgentConfigEntries(root: JsonObject): JsonArray {
    match (root.get("agents")) {
        case Some(v) =>
            try {
                let agents = v.asObject()
                match (agents.get("list")) {
                    case Some(listValue) =>
                        try { listValue.asArray() } catch (_e: Exception) { JsonArray([]) }
                    case None => JsonArray([])
                }
            } catch (_e: Exception) {
                JsonArray([])
            }
        case None => JsonArray([])
    }
}

private func gatewayAgentConfigBindings(root: JsonObject): JsonArray {
    match (root.get("bindings")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func gatewayAgentConfigWriteEntries(root: JsonObject, entries: JsonArray): Unit {
    let agents = match (root.get("agents")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    agents.put("list", entries)
    root.put("agents", agents)
}

private func gatewayAgentConfigWriteBindings(root: JsonObject, bindings: JsonArray): Unit {
    root.put("bindings", bindings)
}

private func gatewayAgentConfigFindEntryIndex(entries: JsonArray, agentId: String): Int64 {
    let normalized = gatewaySanitizeAgentId(agentId)
    for (i in 0..entries.size()) {
        let obj = try {
            entries[i].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        if (gatewaySanitizeAgentId(gatewayAgentJsonString(obj, "id", "")) == normalized) {
            return i
        }
    }
    -1
}

private func gatewayAgentConfigEntry(root: JsonObject, agentId: String): JsonObject {
    let entries = gatewayAgentConfigEntries(root)
    let index = gatewayAgentConfigFindEntryIndex(entries, agentId)
    if (index < 0) {
        return JsonObject()
    }
    try {
        entries[index].asObject()
    } catch (_e: Exception) {
        JsonObject()
    }
}

private func gatewayAgentSummaryModelJson(model: String): JsonObject {
    let out = JsonObject()
    let primary = model.trimAscii()
    if (!primary.isEmpty()) {
        out.put("primary", JsonString(primary))
    }
    out
}

private func gatewayAgentSkillsJson(agentId: String): JsonObject {
    let resolved = resolveAgentSkillVisibility(agentId)
    let out = JsonObject()
    out.put("scope", JsonString(resolved.scope))
    match (resolved.names) {
        case Some(names) =>
            let rows = JsonArray([])
            for (name in names) {
                rows.add(JsonString(name))
            }
            out.put("names", rows)
        case None => ()
    }
    out
}

private func gatewayMainRuntimeProfileJson(): JsonObject {
    let result = JsonObject()
    let gatewayUser = CliSettingManager.readGatewaySettings()
    let required = JsonArray([])
    for (name in gatewayMainRuntimeRequiredToolNames()) {
        required.add(JsonString(name))
    }
    let currentNames = gatewayDefaultChatToolNames()
    let effectiveNames = gatewayAuthorizedChatToolNames()
    let authorizationProfile = gatewayMainRuntimeAuthorizationProfileJson(gatewayUser, currentNames, effectiveNames)
    let current = JsonArray([])
    for (name in currentNames) {
        current.add(JsonString(name))
    }
    let effective = JsonArray([])
    for (name in effectiveNames) {
        effective.add(JsonString(name))
    }
    let missing = JsonArray([])
    for (name in missingRuntimeToolNames(currentNames, gatewayMainRuntimeRequiredToolNames())) {
        missing.add(JsonString(name))
    }
    let extended = JsonArray([])
    for (name in gatewayMainRuntimeExtendedToolNames()) {
        extended.add(JsonString(name))
    }
    let missingExtended = JsonArray([])
    for (name in missingRuntimeToolNames(currentNames, gatewayMainRuntimeExtendedToolNames())) {
        missingExtended.add(JsonString(name))
    }
    let ingresses = JsonArray([])
    for ((ingressId, ingressSource, ingressChannel) in [
        ("cli", "cli", "cli"),
        ("qq", "channel:qq", "qq"),
        ("feishu", "channel:feishu", "feishu"),
        ("control-ui", "control-ui", "cli"),
        ("dashboard", "dashboard", "cli")
    ]) {
        let row = JsonObject()
        row.put("id", JsonString(ingressId))
        row.put("source", JsonString(ingressSource))
        row.put("channel", JsonString(ingressChannel))
        row.put("runtime", JsonString("gateway-main"))
        row.put("agent", JsonString("GatewayP1ChatAgent"))
        row.put("sharesGatewayMainRuntime", true.toJsonValue())
        row.put("toolCount", currentNames.size.toJsonValue())
        row.put("coversUnifiedCoreBaseline", gatewayDefaultChatRuntimeHasUnifiedCoreTools().toJsonValue())
        let capabilities = JsonArray([])
        for (capability in gatewayCorePromptRuntimeCapabilities(gatewayUser, ingressChannel)) {
            capabilities.add(JsonString(capability))
        }
        row.put("capabilities", capabilities)
        row.put("capabilityScope", JsonString("delivery-only"))
        let tools = JsonArray([])
        for (name in currentNames) {
            tools.add(JsonString(name))
        }
        row.put("tools", tools)
        row.put("effectiveTools", effective)
        let promptProfile = JsonObject()
        promptProfile.put("template", JsonString(gatewayMainRuntimePromptTemplateId()))
        promptProfile.put("sharedBasePrompt", true.toJsonValue())
        let differsOnlyBy = JsonArray([])
        for (field in gatewayMainRuntimePromptVarianceFields()) {
            differsOnlyBy.add(JsonString(field))
        }
        promptProfile.put("differsOnlyBy", differsOnlyBy)
        row.put("promptProfile", promptProfile)
        row.put("authorizationProfile", authorizationProfile)
        ingresses.add(row)
    }
    result.put("kind", JsonString("gateway-main-runtime-profile"))
    result.put("runtime", JsonString("gateway-main"))
    result.put("requiredCoreTools", required)
    result.put("currentTools", current)
    result.put("effectiveTools", effective)
    result.put("missingCoreTools", missing)
    result.put("extendedSurfaceTools", extended)
    result.put("missingExtendedSurfaceTools", missingExtended)
    result.put("coversUnifiedCoreBaseline", gatewayDefaultChatRuntimeHasUnifiedCoreTools().toJsonValue())
    result.put("authorizationProfile", authorizationProfile)
    result.put("ingresses", ingresses)
    result
}

private func gatewayMainRuntimeAuditJson(): JsonObject {
    let audit = JsonObject()
    let runtime = gatewayMainRuntimeProfileJson()
    let summary = JsonObject()
    let closure = JsonObject()
    let consumers = JsonObject()
    let remainingSummary = JsonObject()
    summary.put("kind", JsonString("gateway-main-runtime-audit"))
    summary.put("phase", JsonString("G8"))
    summary.put("defaultRuntime", JsonString("gateway-main"))
    summary.put("defaultAgent", JsonString("GatewayP1ChatAgent"))
    summary.put("coversUnifiedCoreBaseline", runtime.get("coversUnifiedCoreBaseline") ?? false.toJsonValue())
    summary.put("sharedPromptTemplate", JsonString(gatewayMainRuntimePromptTemplateId()))
    summary.put("embeddedMode", JsonString("explicit-local-fallback"))
    summary.put("embeddedIsPrimary", false.toJsonValue())
    closure.put("defaultIngressesShareGatewayMain", true.toJsonValue())
    closure.put("embeddedLocalIsFallbackOnly", true.toJsonValue())
    closure.put("docsHelpRuntimeProfileAligned", true.toJsonValue())
    closure.put("registeredAndExecutedToolsDistinguished", true.toJsonValue())
    closure.put("policyFilteringEnforcedAtRuntime", true.toJsonValue())
    closure.put("gatewayActionPolicyExposedAcrossConsumers", true.toJsonValue())
    closure.put("gatewayOwnerAndExplicitInferenceUsesRuntimeContext", true.toJsonValue())
    closure.put("gatewayActionPolicyUsesOperatorScopesAndDeclaredUser", true.toJsonValue())
    consumers.put("agentsRuntimeAudit", true.toJsonValue())
    consumers.put("dashboardAgentsRuntimeAudit", true.toJsonValue())
    consumers.put("controlUiHttpAudit", true.toJsonValue())
    consumers.put("controlUiWsAudit", true.toJsonValue())
    remainingSummary.put("deeperControlSurfaces", true.toJsonValue())
    remainingSummary.put("managedSessionAndAcpConvergence", true.toJsonValue())
    remainingSummary.put("channelSmokeTestsOutsideContractLane", true.toJsonValue())
    let acceptance = JsonArray([])
    for (line in [
        "default-ingresses-share-gateway-main",
        "embedded-local-is-fallback-only",
        "docs-help-runtime-profile-are-aligned",
        "registered-tools-and-executed-tools-are-distinguished",
        "audit-consumers-share-the-same-closure-surface",
        "gateway-action-policy-is-visible-across-runtime-consumers",
        "gateway-owner-and-explicit-inference-use-runtime-context",
        "gateway-owner-inference-consumes-operator-scopes-and-declared-user"
    ]) {
        acceptance.add(JsonString(line))
    }
    let remaining = JsonArray([])
    for (line in [
        "gateway main runtime deeper control surfaces can still be refined",
        "managed session and ACP ecosystem can continue to converge",
        "channel-level smoke tests should continue outside unit and contract regression lanes",
        "automatic owner and explicit-request inference can continue to converge with approval-surface callbacks and richer sender identity guarantees"
    ]) {
        remaining.add(JsonString(line))
    }
    summary.put("closure", closure)
    summary.put("consumers", consumers)
    summary.put("acceptanceCount", acceptance.size().toJsonValue())
    summary.put("remainingCount", remaining.size().toJsonValue())
    audit.put("kind", JsonString("gateway-main-runtime-audit"))
    audit.put("summary", summary)
    audit.put("runtime", runtime)
    audit.put("acceptance", acceptance)
    audit.put("remaining", remaining)
    audit.put("remainingSummary", remainingSummary)
    audit
}

private func gatewayMainRuntimeGatewayActionPolicyJson(): JsonObject {
    let out = JsonObject()
    let readOnly = JsonArray([])
    for (name in ["status", "health", "discover", "discover.detail", "config.get", "config.schema.lookup"]) {
        readOnly.add(JsonString(name))
    }
    let ownerApproved = JsonArray([])
    for (name in ["start", "stop", "restart", "master_on", "master_off", "config.patch", "config.apply", "update.run"]) {
        ownerApproved.add(JsonString(name))
    }
    let explicitRequest = JsonArray([])
    for (name in ["config.patch", "config.apply", "update.run"]) {
        explicitRequest.add(JsonString(name))
    }
    let protectedPaths = JsonArray([])
    for (path in [
        "gateway.controlUi.allowInsecureAuth",
        "gateway.controlUi.dangerouslyDisableDeviceAuth",
        "gateway.auth.mode",
        "gateway.auth.allowTailscale"
    ]) {
        protectedPaths.add(JsonString(path))
    }
    out.put("mode", JsonString("owner-policy-approval-protected-path"))
    out.put("visibleOnUnifiedRuntime", true.toJsonValue())
    out.put("mutationExecutionMode", JsonString("guarded"))
    out.put("rejectionContract", JsonString("deny-with-reason"))
    out.put("readOnlyActions", readOnly)
    out.put("ownerApprovedActions", ownerApproved)
    out.put("explicitRequestActions", explicitRequest)
    let autoOwnerSources = JsonArray([])
    for (name in ["cli", "control-ui", "dashboard", "cron"]) {
        autoOwnerSources.add(JsonString(name))
    }
    let ownerSignals = JsonArray([])
    for (name in ["operator-scopes", "declared-user+trusted-ingress", "ingress-fallback"]) {
        ownerSignals.add(JsonString(name))
    }
    out.put("autoOwnerApprovedSources", autoOwnerSources)
    out.put("ownerAuthorizationSignals", ownerSignals)
    out.put("ownerInferenceMode", JsonString("runtime-ingress-derived"))
    out.put("explicitRequestInference", JsonString("runtime-context-prompt-derived"))
    out.put("contextIdentityFields", JsonArray([JsonString("declaredUser"), JsonString("operatorScopes"), JsonString("senderId"), JsonString("sourceLabel")]))
    out.put("protectedConfigPaths", protectedPaths)
    out
}

private func gatewayMainRuntimeAuthorizationProfileJson(
    user: GatewayUserSettings,
    currentNames: Array<String>,
    effectiveNames: Array<String>
): JsonObject {
    let out = JsonObject()
    let cfg = buildGatewayConfigFromUserSettings(user)
    let allow = JsonArray([])
    let normalizedAllow = HashMap<String, Bool>()
    for (name in user.tools.allow) {
        let normalized = name.trimAscii()
        if (!normalized.isEmpty()) {
            allow.add(JsonString(normalized))
            normalizedAllow[normalized] = true
        }
    }
    let deny = JsonArray([])
    var denyAllTools = false
    let normalizedDeny = HashMap<String, Bool>()
    for (name in user.tools.deny) {
        let normalized = name.trimAscii()
        if (normalized.isEmpty()) {
            continue
        }
        if (normalized == "*") {
            denyAllTools = true
        } else {
            normalizedDeny[normalized] = true
        }
        deny.add(JsonString(normalized))
    }
    let effectiveSet = HashMap<String, Bool>()
    let authorizedTools = JsonArray([])
    for (toolName in effectiveNames) {
        effectiveSet[toolName] = true
        authorizedTools.add(JsonString(toolName))
    }
    let restrictedTools = JsonArray([])
    for (toolName in currentNames) {
        if (!effectiveSet.contains(toolName)) {
            restrictedTools.add(JsonString(toolName))
        }
    }
    let controls = JsonArray([])
    for (name in ["tools-allow-deny", "channel-policy", "approval", "sandbox"]) {
        controls.add(JsonString(name))
    }
    out.put("toolAvailability", JsonString("registered-unified"))
    out.put("authorizationModel", JsonString("policy-gated"))
    out.put("rejectionContract", JsonString("deny-with-reason"))
    out.put("enforcementStage", JsonString("runtime-tool-filter"))
    out.put("toolsPolicyMode", JsonString(if (allow.size() == 0) { "allow-all-registered" } else { "allowlist" }))
    out.put("toolsAllow", allow)
    out.put("toolsDeny", deny)
    out.put("denyAllTools", denyAllTools.toJsonValue())
    out.put("authorizedTools", authorizedTools)
    out.put("restrictedTools", restrictedTools)
    out.put("channelPolicyCount", cfg.policyByChannel.size.toJsonValue())
    out.put("approvalSurface", JsonString("native-or-manual"))
    out.put("sandboxEnforcement", JsonString("runtime-reported"))
    out.put("controls", controls)
    out.put("gatewayActionPolicy", gatewayMainRuntimeGatewayActionPolicyJson())
    out
}

private func gatewayAgentSummaryRow(agentId: String, kind: String, entry!: JsonObject = JsonObject()): JsonObject {
    let row = JsonObject()
    let normalized = gatewaySanitizeAgentId(agentId)
    row.put("id", JsonString(normalized))
    let configuredName = gatewayAgentJsonString(entry, "name", "").trimAscii()
    if (!configuredName.isEmpty()) {
        row.put("name", JsonString(configuredName))
    }
    match (entry.get("identity")) {
        case Some(v) =>
            try {
                row.put("identity", v.asObject())
            } catch (_e: Exception) {
                ()
            }
        case None => ()
    }
    let configuredWorkspace = gatewayAgentJsonString(entry, "workspace", "").trimAscii()
    if (!configuredWorkspace.isEmpty()) {
        row.put("workspace", JsonString(configuredWorkspace))
    }
    let model = gatewayAgentJsonString(entry, "model", "").trimAscii()
    let modelJson = gatewayAgentSummaryModelJson(model)
    if (modelJson.size() > 0) {
        row.put("model", modelJson)
    }
    row.put("skills", gatewayAgentSkillsJson(normalized))
    row.put("kind", JsonString(kind))
    row
}

private func gatewayAgentsContractJson(): JsonObject {
    let root = gatewayAgentConfigRootCloneReadOnly()
    let scopeSummary = MetisAgentScope.summary(root, homeRoot: MetisPaths.homeRootReadOnly(), defaultWorkspace: MetisPaths.workspaceRootReadOnly())
    let agents = JsonArray([])
    for (agentId in [
        "main",
        "cangjie",
        "explorer",
        "editor",
        "reviewer",
        "test_generator",
        "refactoring",
        "planner"
    ]) {
        agents.add(gatewayAgentSummaryRow(agentId, "builtin"))
    }
    for (agentDir in CliConfig.subagentDirs) {
        if (!exists(agentDir)) {
            continue
        }
        for (entry in Directory.readFrom(agentDir)) {
            if (!entry.isDirectory()) {
                continue
            }
            let manifest = agentDir.join(entry.name).join("AGENT.md")
            if (!exists(manifest)) {
                continue
            }
            let configuredEntry = gatewayAgentConfigEntry(root, entry.name)
            agents.add(gatewayAgentSummaryRow(entry.name, "custom", entry: configuredEntry))
        }
    }
    let result = JsonObject()
    result.put("defaultId", scopeSummary.get("defaultAgentId") ?? JsonString("main"))
    result.put("mainKey", JsonString("main"))
    result.put("scope", JsonString("global"))
    result.put("agents", agents)
    result
}

private func gatewayAgentExists(root: JsonObject, agentId: String): Bool {
    let normalized = gatewaySanitizeAgentId(agentId)
    if (gatewayAgentJsonBool(gatewayAgentGetJson(normalized), "configured", false)) {
        return true
    }
    gatewayAgentConfigFindEntryIndex(gatewayAgentConfigEntries(root), normalized) >= 0
}

private func gatewayAgentDefaultAgentDir(agentId: String): Path {
    MetisPaths.homeRoot().join("agents").join(gatewaySanitizeAgentId(agentId)).join("agent")
}

private func gatewayAgentDefaultSessionsDir(agentId: String): Path {
    MetisPaths.homeRoot().join("agents").join(gatewaySanitizeAgentId(agentId)).join("sessions")
}

private func gatewayAgentDefaultWorkspaceDir(agentId: String): Path {
    MetisPaths.homeRoot().join("workspaces").join(gatewaySanitizeAgentId(agentId))
}

private func gatewayAgentBuildDefaultManifest(agentId: String, name: String, workspace: String): String {
    let title = if (name.trimAscii().isEmpty()) { agentId } else { name.trimAscii() }
    "name: ${title}\n" +
    "description: Custom agent ${gatewaySanitizeAgentId(agentId)}\n" +
    "tools: listDirectory,fileRead,globSearch,grepSearch\n" +
    "---\n" +
    "# ${title}\n\n" +
    "This custom agent is managed by Metis.\n\n" +
    "Workspace: ${workspace}\n"
}

private func gatewayAgentBootstrapFilesJson(bootstrap: MetisAgentWorkspaceBootstrapResult): JsonArray {
    let files = JsonArray([])
    for (file in bootstrap.files) {
        let row = JsonObject()
        row.put("name", JsonString(file.name))
        row.put("path", JsonString(file.path))
        row.put("created", file.created.toJsonValue())
        row.put("existed", file.existed.toJsonValue())
        files.add(row)
    }
    files
}

private func gatewayAgentBindingAccountId(matchObj: JsonObject): String {
    let value = gatewayAgentJsonString(matchObj, "accountId", "").trimAscii()
    if (value.isEmpty()) { "default" } else { value }
}

private func gatewayAgentBindingMatchKey(binding: JsonObject): String {
    let matchObj = match (binding.get("match")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let channel = gatewayAgentJsonString(matchObj, "channel", "").trimAscii().toAsciiLower()
    let accountId = gatewayAgentBindingAccountId(matchObj).trimAscii().toAsciiLower()
    "${channel}|${accountId}"
}

private func gatewayAgentBindingDescribe(binding: JsonObject): String {
    let matchObj = match (binding.get("match")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let channel = gatewayAgentJsonString(matchObj, "channel", "")
    let accountId = gatewayAgentJsonString(matchObj, "accountId", "")
    if (accountId.trimAscii().isEmpty()) {
        channel
    } else {
        "${channel}:${accountId.trimAscii()}"
    }
}

private func gatewayAgentBindingSpecs(request: GatewayRpcRequest): Array<String> {
    let out = ArrayList<String>()
    for (key in ["bind", "bindings"]) {
        match (request.params.get(key)) {
            case Some(v) =>
                try {
                    let arr = v.asArray()
                    for (i in 0..arr.size()) {
                        try {
                            let item = arr[i].asString().getValue().trimAscii()
                            if (!item.isEmpty()) {
                                out.add(item)
                            }
                        } catch (_inner: Exception) {
                            ()
                        }
                    }
                } catch (_e: Exception) {
                    try {
                        let item = v.asString().getValue().trimAscii()
                        if (!item.isEmpty()) {
                            out.add(item)
                        }
                    } catch (_inner: Exception) {
                        ()
                    }
                }
            case None => ()
        }
    }
    out.toArray()
}

private func gatewayAgentParseBindingSpecs(agentId: String, request: GatewayRpcRequest): (JsonArray, JsonArray) {
    let bindings = JsonArray([])
    let errors = JsonArray([])
    for (spec in gatewayAgentBindingSpecs(request)) {
        let trimmed = spec.trimAscii()
        if (trimmed.isEmpty()) {
            continue
        }
        let parts = trimmed.split(":")
        let channel = parts[0].trimAscii().toAsciiLower()
        if (channel.isEmpty()) {
            errors.add(JsonString("Invalid binding spec: ${trimmed}"))
            continue
        }
        let accountId = if (parts.size >= 2) {
            String.join(parts[1..parts.size], delimiter: ":").trimAscii()
        } else {
            ""
        }
        let matchObj = JsonObject()
        matchObj.put("channel", JsonString(channel))
        if (!accountId.isEmpty()) {
            matchObj.put("accountId", JsonString(accountId))
        }
        let binding = JsonObject()
        binding.put("agentId", JsonString(gatewaySanitizeAgentId(agentId)))
        binding.put("match", matchObj)
        bindings.add(binding)
    }
    (bindings, errors)
}

private func gatewayAgentBindingsListJson(request: GatewayRpcRequest): JsonObject {
    let root = gatewayAgentConfigRootClone()
    let filterAgentId = gatewaySanitizeAgentId(gatewayAgentRpcStringParam(request, ["agent", "agentId"], ""))
    let out = JsonArray([])
    let bindings = gatewayAgentConfigBindings(root)
    for (i in 0..bindings.size()) {
        let binding = try {
            bindings[i].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let bindingAgentId = gatewaySanitizeAgentId(gatewayAgentJsonString(binding, "agentId", ""))
        if (!filterAgentId.isEmpty() && bindingAgentId != filterAgentId) {
            continue
        }
        let row = JsonObject()
        row.put("agentId", JsonString(bindingAgentId))
        row.put("match", binding.get("match") ?? JsonObject())
        row.put("description", JsonString(gatewayAgentBindingDescribe(binding)))
        out.add(row)
    }
    let result = JsonObject()
    result.put("bindings", out)
    result.put("count", out.size().toJsonValue())
    result
}

private func gatewayAgentBindingsApplyJson(request: GatewayRpcRequest): GatewayRpcResponse {
    let root = gatewayAgentConfigRootClone()
    let agentId = gatewaySanitizeAgentId(gatewayAgentRpcStringParam(request, ["agent", "agentId"], ""))
    if (agentId.isEmpty()) {
        return GatewayRpcResponse(false, "agents.bind", error: "Agent id is required.")
    }
    if (!gatewayAgentExists(root, agentId)) {
        return GatewayRpcResponse(false, "agents.bind", error: "Agent \"${agentId}\" not found.")
    }
    let (incoming, errors) = gatewayAgentParseBindingSpecs(agentId, request)
    if (incoming.size() == 0) {
        return GatewayRpcResponse(false, "agents.bind", error: "Provide at least one --bind <channel[:accountId]>.")
    }
    if (errors.size() > 0) {
        return GatewayRpcResponse(false, "agents.bind", error: errors.toJsonString())
    }
    let existing = gatewayAgentConfigBindings(root)
    let next = JsonArray([])
    for (i in 0..existing.size()) {
        next.add(existing[i])
    }
    let added = JsonArray([])
    let skipped = JsonArray([])
    let conflicts = JsonArray([])
    for (i in 0..incoming.size()) {
        let binding = try {
            incoming[i].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let matchKey = gatewayAgentBindingMatchKey(binding)
        let bindingAgentId = gatewaySanitizeAgentId(gatewayAgentJsonString(binding, "agentId", ""))
        var matched = false
        for (j in 0..next.size()) {
            let current = try {
                next[j].asObject()
            } catch (_e: Exception) {
                JsonObject()
            }
            if (gatewayAgentBindingMatchKey(current) != matchKey) {
                continue
            }
            matched = true
            let currentAgentId = gatewaySanitizeAgentId(gatewayAgentJsonString(current, "agentId", ""))
            if (currentAgentId == bindingAgentId) {
                skipped.add(JsonString(gatewayAgentBindingDescribe(binding)))
            } else {
                let conflict = JsonObject()
                conflict.put("binding", JsonString(gatewayAgentBindingDescribe(binding)))
                conflict.put("existingAgentId", JsonString(currentAgentId))
                conflicts.add(conflict)
            }
            break
        }
        if (!matched) {
            next.add(binding)
            added.add(JsonString(gatewayAgentBindingDescribe(binding)))
        }
    }
    gatewayAgentConfigWriteBindings(root, next)
    MetisConfigManager.writeRoot(root)
    let result = JsonObject()
    result.put("agentId", JsonString(agentId))
    result.put("added", added)
    result.put("skipped", skipped)
    result.put("conflicts", conflicts)
    result.put("bindings", next)
    GatewayRpcResponse(true, "agents.bind", result: result)
}

private func gatewayAgentBindingsRemoveJson(request: GatewayRpcRequest): GatewayRpcResponse {
    let root = gatewayAgentConfigRootClone()
    let agentId = gatewaySanitizeAgentId(gatewayAgentRpcStringParam(request, ["agent", "agentId"], ""))
    if (agentId.isEmpty()) {
        return GatewayRpcResponse(false, "agents.unbind", error: "Agent id is required.")
    }
    let removeAll = match (request.params.get("all")) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
    let (incoming, errors) = gatewayAgentParseBindingSpecs(agentId, request)
    if (!removeAll && incoming.size() == 0) {
        return GatewayRpcResponse(false, "agents.unbind", error: "Provide at least one --bind <channel[:accountId]> or use --all.")
    }
    if (errors.size() > 0) {
        return GatewayRpcResponse(false, "agents.unbind", error: errors.toJsonString())
    }
    let existing = gatewayAgentConfigBindings(root)
    let next = JsonArray([])
    let removed = JsonArray([])
    let missing = JsonArray([])
    let desiredKeys = ArrayList<String>()
    for (i in 0..incoming.size()) {
        let binding = try {
            incoming[i].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        desiredKeys.add(gatewayAgentBindingMatchKey(binding))
    }
    for (i in 0..existing.size()) {
        let current = try {
            existing[i].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let currentAgentId = gatewaySanitizeAgentId(gatewayAgentJsonString(current, "agentId", ""))
        let currentKey = gatewayAgentBindingMatchKey(current)
        let shouldRemove = if (removeAll) {
            currentAgentId == agentId
        } else {
            currentAgentId == agentId && desiredKeys.contains(currentKey)
        }
        if (shouldRemove) {
            removed.add(JsonString(gatewayAgentBindingDescribe(current)))
        } else {
            next.add(current)
        }
    }
    if (!removeAll) {
        for (key in desiredKeys) {
            var found = false
            for (i in 0..removed.size()) {
                let desc = try {
                    removed[i].asString().getValue()
                } catch (_e: Exception) {
                    ""
                }
                if (desc == key.replace("|", ":")) {
                    found = true
                    break
                }
            }
            if (!found) {
                let pieces = key.split("|")
                let channel = if (pieces.size >= 1) { pieces[0] } else { "" }
                let accountId = if (pieces.size >= 2 && pieces[1] != "default") { pieces[1] } else { "" }
                missing.add(JsonString(if (accountId.isEmpty()) { channel } else { "${channel}:${accountId}" }))
            }
        }
    }
    gatewayAgentConfigWriteBindings(root, next)
    MetisConfigManager.writeRoot(root)
    let result = JsonObject()
    result.put("agentId", JsonString(agentId))
    result.put("removed", removed)
    result.put("missing", missing)
    result.put("bindings", next)
    GatewayRpcResponse(true, "agents.unbind", result: result)
}

private func gatewayAgentAddJson(request: GatewayRpcRequest): GatewayRpcResponse {
    let root = gatewayAgentConfigRootClone()
    let requestedId = gatewayAgentRpcStringParam(request, ["id", "agent", "agentId"], "")
    if (requestedId.trimAscii().isEmpty()) {
        return GatewayRpcResponse(false, "agents.add", error: "Agent id is required.")
    }
    let agentId = gatewaySanitizeAgentId(requestedId)
    let entries = gatewayAgentConfigEntries(root)
    if (gatewayAgentConfigFindEntryIndex(entries, agentId) >= 0 || gatewayAgentJsonBool(gatewayAgentGetJson(agentId), "configured", false)) {
        return GatewayRpcResponse(false, "agents.add", error: "Agent \"${agentId}\" already exists.")
    }
    let name = gatewayAgentRpcStringParam(request, ["name"], agentId)
    let workspace = gatewayAgentRpcStringParam(request, ["workspace"], gatewayAgentDefaultWorkspaceDir(agentId).toString())
    let model = gatewayAgentRpcStringParam(request, ["model"], "")
    let agentDir = gatewayAgentRpcStringParam(request, ["agentDir"], gatewayAgentDefaultAgentDir(agentId).toString())
    let sessionsDir = gatewayAgentRpcStringParam(request, ["sessionsDir"], gatewayAgentDefaultSessionsDir(agentId).toString())
    if (gatewayAgentJsonBool(request.params, "copyAuthProfiles", false) || gatewayAgentJsonBool(request.params, "importAuthProfiles", false)) {
        return GatewayRpcResponse(false, "agents.add", error: "Auth profile copy/import requires an explicit source and is not performed by default.")
    }
    let agentDirPath = Path(agentDir)
    let workspacePath = Path(workspace)
    let sessionsDirPath = Path(sessionsDir)
    if (!exists(agentDirPath)) {
        Directory.create(agentDirPath, recursive: true)
    }
    if (!exists(sessionsDirPath)) {
        Directory.create(sessionsDirPath, recursive: true)
    }
    let bootstrap = ensureMetisAgentWorkspace(workspacePath)
    let manifestPath = agentDirPath.join("AGENT.md")
    if (!exists(manifestPath)) {
        File.writeTo(manifestPath, gatewayAgentBuildDefaultManifest(agentId, name, workspace).toArray())
    }
    let entry = JsonObject()
    entry.put("id", JsonString(agentId))
    entry.put("name", JsonString(name))
    entry.put("workspace", JsonString(workspace))
    entry.put("agentDir", JsonString(agentDir))
    entry.put("sessionsDir", JsonString(sessionsDir))
    if (!model.trimAscii().isEmpty()) {
        entry.put("model", JsonString(model.trimAscii()))
    }
    let nextEntries = JsonArray([])
    for (i in 0..entries.size()) {
        nextEntries.add(entries[i])
    }
    nextEntries.add(entry)
    gatewayAgentConfigWriteEntries(root, nextEntries)
    MetisConfigManager.writeRoot(root)
    let result = JsonObject()
    result.put("agentId", JsonString(agentId))
    result.put("name", JsonString(name))
    result.put("workspace", JsonString(workspace))
    result.put("workspaceDir", JsonString(workspace))
    result.put("agentDir", JsonString(agentDir))
    result.put("sessionsDir", JsonString(sessionsDir))
    result.put("createdManifest", JsonString(manifestPath.toString()))
    let bootstrapJson = JsonObject()
    bootstrapJson.put("workspaceDir", JsonString(bootstrap.workspaceDir))
    bootstrapJson.put("createdCount", bootstrap.createdCount.toJsonValue())
    bootstrapJson.put("files", gatewayAgentBootstrapFilesJson(bootstrap))
    bootstrapJson.put("authProfilesCopied", false.toJsonValue())
    bootstrapJson.put("authProfilesCopyRequiresExplicitRequest", true.toJsonValue())
    bootstrapJson.put("authProfilesPath", JsonString(agentDirPath.join("auth-profiles.json").toString()))
    bootstrapJson.put("modelsJsonPath", JsonString(agentDirPath.join("models.json").toString()))
    result.put("bootstrap", bootstrapJson)
    GatewayRpcResponse(true, "agents.add", result: result)
}

private func gatewayAgentSetIdentityJson(request: GatewayRpcRequest): GatewayRpcResponse {
    let root = gatewayAgentConfigRootClone()
    let agentId = gatewaySanitizeAgentId(gatewayAgentRpcStringParam(request, ["id", "agent", "agentId"], ""))
    if (agentId.isEmpty()) {
        return GatewayRpcResponse(false, "agents.set-identity", error: "Agent id is required.")
    }
    let entries = gatewayAgentConfigEntries(root)
    let index = gatewayAgentConfigFindEntryIndex(entries, agentId)
    if (index < 0) {
        return GatewayRpcResponse(false, "agents.set-identity", error: "Agent \"${agentId}\" not found.")
    }
    let nextEntries = JsonArray([])
    for (i in 0..entries.size()) {
        let entry = try {
            entries[i].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        if (i == index) {
            let identity = match (entry.get("identity")) {
                case Some(v) =>
                    try { v.asObject() } catch (_e: Exception) { JsonObject() }
                case None => JsonObject()
            }
            for (field in ["name", "emoji", "theme", "avatar"]) {
                let value = gatewayAgentRpcStringParam(request, [field], "").trimAscii()
                if (!value.isEmpty()) {
                    identity.put(field, JsonString(value))
                }
            }
            entry.put("identity", identity)
        }
        nextEntries.add(entry)
    }
    gatewayAgentConfigWriteEntries(root, nextEntries)
    MetisConfigManager.writeRoot(root)
    let updated = try {
        nextEntries[index].asObject()
    } catch (_e: Exception) {
        JsonObject()
    }
    let result = JsonObject()
    result.put("agentId", JsonString(agentId))
    result.put("identity", updated.get("identity") ?? JsonObject())
    GatewayRpcResponse(true, "agents.set-identity", result: result)
}

private func gatewayAgentDeleteJson(request: GatewayRpcRequest): GatewayRpcResponse {
    let root = gatewayAgentConfigRootClone()
    let agentId = gatewaySanitizeAgentId(gatewayAgentRpcStringParam(request, ["id", "agent", "agentId"], ""))
    if (agentId.isEmpty()) {
        return GatewayRpcResponse(false, "agents.delete", error: "Agent id is required.")
    }
    if (agentId == "main" || agentId == "general") {
        return GatewayRpcResponse(false, "agents.delete", error: "Agent \"${agentId}\" cannot be deleted.")
    }
    let entries = gatewayAgentConfigEntries(root)
    let nextEntries = JsonArray([])
    var removedEntry = JsonObject()
    var found = false
    for (i in 0..entries.size()) {
        let entry = try {
            entries[i].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        if (gatewaySanitizeAgentId(gatewayAgentJsonString(entry, "id", "")) == agentId) {
            found = true
            removedEntry = entry
            continue
        }
        nextEntries.add(entry)
    }
    if (!found) {
        return GatewayRpcResponse(false, "agents.delete", error: "Agent \"${agentId}\" not found.")
    }
    let bindings = gatewayAgentConfigBindings(root)
    let nextBindings = JsonArray([])
    var removedBindings: Int64 = 0
    for (i in 0..bindings.size()) {
        let binding = try {
            bindings[i].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        if (gatewaySanitizeAgentId(gatewayAgentJsonString(binding, "agentId", "")) == agentId) {
            removedBindings += 1
            continue
        }
        nextBindings.add(binding)
    }
    gatewayAgentConfigWriteEntries(root, nextEntries)
    gatewayAgentConfigWriteBindings(root, nextBindings)
    MetisConfigManager.writeRoot(root)
    let agentDir = gatewayAgentJsonString(removedEntry, "agentDir", "")
    let workspace = gatewayAgentJsonString(removedEntry, "workspace", "")
    let homeRoot = MetisPaths.homeRoot().toString()
    if (!agentDir.trimAscii().isEmpty() && agentDir.startsWith(homeRoot) && exists(Path(agentDir))) {
        remove(Path(agentDir), recursive: true)
    }
    if (!workspace.trimAscii().isEmpty() && workspace.startsWith(homeRoot) && exists(Path(workspace))) {
        remove(Path(workspace), recursive: true)
    }
    let result = JsonObject()
    result.put("agentId", JsonString(agentId))
    result.put("removedBindings", removedBindings.toJsonValue())
    result.put("agentDir", JsonString(agentDir))
    result.put("workspace", JsonString(workspace))
    GatewayRpcResponse(true, "agents.delete", result: result)
}

public func gatewayBuildAgentInvokeRpcParams(
    source: GatewayIngressSource,
    sessionKey!: String = "",
    text!: String = "",
    channel!: String = "gateway-rpc",
    agentId!: String = "",
    conversationId!: String = "",
    threadId!: String = "",
    sourceMessageId!: String = "",
    to!: String = "",
    lane!: String = "",
    deliver!: Bool = false,
    thinking!: String = "",
    verbose!: String = "",
    timeoutSeconds!: Int64 = 0,
    bestEffortDeliver!: Bool = false,
    replyChannel!: String = "",
    replyTo!: String = "",
    replyAccount!: String = "",
    replyToMessageId!: String = "",
    replyInThread!: Bool = false,
    extraSystemPrompt!: String = "",
    idempotencyKey!: String = ""
): JsonObject {
    let params = gatewayBuildSessionRpcParams(
        source,
        session: sessionKey,
        text: text,
        channel: channel,
        agentId: agentId,
        conversationId: conversationId,
        threadId: threadId,
        sourceMessageId: sourceMessageId,
        to: to,
        lane: lane,
        deliver: deliver,
        thinking: thinking,
        verbose: verbose,
        timeoutSeconds: timeoutSeconds,
        bestEffortDeliver: bestEffortDeliver,
        replyChannel: replyChannel,
        replyTo: replyTo,
        replyAccount: replyAccount,
        replyToMessageId: replyToMessageId,
        replyInThread: replyInThread,
        extraSystemPrompt: extraSystemPrompt,
        idempotencyKey: idempotencyKey
    )
    params.put("sessionKey", JsonString(sessionKey.trimAscii()))
    params
}

private func gatewayAgentInvokeParams(agentId: String, request: GatewayRpcRequest): JsonObject {
    let source = gatewayIngressSourceFromString(
        gatewayAgentRpcStringParam(request, ["source"], "gateway-rpc"),
        fallback: GatewayIngressSource.GatewayRpc
    )
    let timeoutSeconds = match (request.params.get("timeout")) {
        case Some(v) =>
            try { Int64.parse(v.asString().getValue()) } catch (_e: Exception) {
                try { Int64.parse(v.toJsonString()) } catch (_e2: Exception) { 0 }
            }
        case None => 0
    }
    let deliver = match (request.params.get("deliver")) {
        case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
    let bestEffortDeliver = match (request.params.get("bestEffortDeliver")) {
        case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
    gatewayBuildAgentInvokeRpcParams(
        source,
        sessionKey: gatewayAgentRpcStringParam(request, ["sessionKey", "session", "sessionId"], ""),
        text: gatewayAgentRpcStringParam(request, ["text", "prompt", "message"], ""),
        channel: gatewayAgentRpcStringParam(request, ["channel"], "gateway-rpc"),
        agentId: agentId,
        conversationId: gatewayAgentRpcStringParam(request, ["conversationId"], ""),
        threadId: gatewayAgentRpcStringParam(request, ["threadId"], ""),
        sourceMessageId: gatewayAgentRpcStringParam(request, ["sourceMessageId"], ""),
        to: gatewayAgentRpcStringParam(request, ["to"], ""),
        lane: gatewayAgentRpcStringParam(request, ["lane"], ""),
        deliver: deliver,
        thinking: gatewayAgentRpcStringParam(request, ["thinking"], ""),
        verbose: gatewayAgentRpcStringParam(request, ["verbose"], ""),
        timeoutSeconds: timeoutSeconds,
        bestEffortDeliver: bestEffortDeliver,
        replyChannel: gatewayAgentRpcStringParam(request, ["replyChannel"], ""),
        replyTo: gatewayAgentRpcStringParam(request, ["replyTo"], ""),
        replyAccount: gatewayAgentRpcStringParam(request, ["replyAccount", "replyAccountId"], ""),
        replyToMessageId: gatewayAgentRpcStringParam(request, ["replyToMessageId"], ""),
        replyInThread: gatewayAgentRpcStringParam(request, ["replyInThread"], "").toAsciiLower() == "true",
        extraSystemPrompt: gatewayAgentRpcStringParam(request, ["extraSystemPrompt"], ""),
        idempotencyKey: gatewayAgentRpcStringParam(request, ["idempotencyKey", "runId"], "")
    )
}

private func gatewayAgentInvokeContext(agentId: String, request: GatewayRpcRequest) {
    let params = gatewayAgentInvokeParams(agentId, request)
    gatewayResolveSessionContext(gatewaySessionRequestFromRpcParams(params, fallbackSource: GatewayIngressSource.GatewayRpc))
}

public func gatewayAgentResolvedInvokeParams(agentId: String, request: GatewayRpcRequest): JsonObject {
    let params = gatewayAgentInvokeParams(agentId, request)
    let context = gatewayResolveSessionContext(gatewaySessionRequestFromRpcParams(params, fallbackSource: GatewayIngressSource.GatewayRpc))
    params.put("session", JsonString(context.sessionKey))
    params
}

private func gatewayBuiltinAgentsJson(): JsonArray {
    let names = [
        "main",
        "cangjie",
        "explorer",
        "editor",
        "reviewer",
        "test_generator",
        "refactoring",
        "planner"
    ]
    let out = JsonArray([])
    for (name in names) {
        let row = JsonObject()
        row.put("id", JsonString(name))
        row.put("kind", JsonString("builtin"))
        row.put("available", true.toJsonValue())
        row.put("configured", true.toJsonValue())
        row.put("health", JsonString("ok"))
        row.put("capabilities", gatewayBuiltinAgentCapabilities(name))
        out.add(row)
    }
    out
}

private func gatewayBuiltinAgentCapabilities(agentId: String): JsonArray {
    let out = JsonArray([])
    match (agentId.trimAscii().toAsciiLower()) {
        case "main" | "general" =>
            out.add(JsonString("chat"))
            out.add(JsonString("tools"))
        case "cangjie" =>
            out.add(JsonString("chat"))
            out.add(JsonString("cangjie"))
            out.add(JsonString("tools"))
        case "explorer" =>
            out.add(JsonString("search"))
            out.add(JsonString("read-only"))
        case "editor" =>
            out.add(JsonString("edit"))
        case "reviewer" =>
            out.add(JsonString("review"))
        case "test_generator" =>
            out.add(JsonString("tests"))
        case "refactoring" =>
            out.add(JsonString("refactor"))
        case "planner" =>
            out.add(JsonString("plan"))
        case _ => ()
    }
    out
}

private func gatewayCustomAgentsJson(): JsonArray {
    let out = JsonArray([])
    for (agentDir in CliConfig.subagentDirs) {
        if (!exists(agentDir)) {
            continue
        }
        for (entry in Directory.readFrom(agentDir)) {
            if (!entry.isDirectory()) {
                continue
            }
            let manifest = agentDir.join(entry.name).join("AGENT.md")
            if (!exists(manifest)) {
                continue
            }
            let row = JsonObject()
            row.put("id", JsonString(entry.name))
            row.put("kind", JsonString("custom"))
            row.put("path", JsonString(agentDir.join(entry.name).toString()))
            row.put("available", true.toJsonValue())
            row.put("configured", true.toJsonValue())
            row.put("health", JsonString("ok"))
            row.put("memory", gatewayAgentMemoryJson(entry.name))
            out.add(row)
        }
    }
    out
}

private func gatewayAgentMemoryJson(agentId: String): JsonObject {
    let normalized = gatewaySanitizeAgentId(agentId)
    let out = JsonObject()
    out.put(
        "resolvedBackendConfig",
        MemoryRuntimeRegistry.resolveBackendConfig(
            agentId: normalized,
            purpose: "agents-inspect"
        ).toJsonObject()
    )
    out.put(
        "backendSelection",
        MemoryRuntimeRegistry.backendSelectionSummary(
            agentId: normalized,
            purpose: "agents-inspect"
        )
    )
    out.put(
        "agentScopedResolve",
        MemoryRuntimeRegistry.agentScopedResolveSummary(
            agentId: normalized,
            purpose: "agents-inspect"
        )
    )
    out.put(
        "activeMemoryPlugin",
        MemoryRuntimeRegistry.activeMemoryPluginSummary(
            agentId: normalized,
            purpose: "agents-inspect"
        )
    )
    out.put(
        "activeSearchBackend",
        MemoryRuntimeRegistry.activeSearchBackendSummary(
            agentId: normalized,
            purpose: "agents-inspect"
        )
    )
    out.put(
        "activeOrchestrationBackend",
        MemoryRuntimeRegistry.activeOrchestrationBackendSummary(
            agentId: normalized,
            purpose: "agents-inspect"
        )
    )
    out
}

private func gatewayAgentGetJson(agentId: String): JsonObject {
    let normalized = agentId.trimAscii().toAsciiLower()
    let builtins = gatewayBuiltinAgentsJson()
    for (i in 0..builtins.size()) {
        let item = builtins[i]
        let obj = try {
            item.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let id = match (obj.get("id")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_inner: Exception) { "" }
            case None => ""
        }
        if (id == normalized) {
            let row = JsonObject()
            row.put("id", JsonString(id))
            row.put("kind", JsonString("builtin"))
            row.put("capabilities", gatewayBuiltinAgentCapabilities(id))
            row.put("configured", true.toJsonValue())
            row.put("skills", gatewayAgentSkillsJson(id))
            row.put("memory", gatewayAgentMemoryJson(id))
            return row
        }
    }
    let customs = gatewayCustomAgentsJson()
    for (i in 0..customs.size()) {
        let item = customs[i]
        let obj = try {
            item.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let id = match (obj.get("id")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_inner: Exception) { "" }
            case None => ""
        }
        if (id == normalized) {
            let row = JsonObject()
            row.put("id", JsonString(id))
            row.put("kind", JsonString("custom"))
            row.put("path", obj.get("path") ?? JsonString(""))
            row.put("configured", true.toJsonValue())
            row.put("skills", gatewayAgentSkillsJson(id))
            row.put("memory", gatewayAgentMemoryJson(id))
            return row
        }
    }
    let row = JsonObject()
    row.put("id", JsonString(normalized))
    row.put("configured", false.toJsonValue())
    row
}

private func gatewayAgentPreviewJson(agentId: String, request: GatewayRpcRequest): JsonObject {
    let row = gatewayAgentGetJson(agentId)
    let preview = JsonObject()
    preview.put("agent", row)
    preview.put("sessionKey", JsonString(gatewayAgentRpcStringParam(request, ["sessionKey", "session"], "main")))
    preview.put("channel", JsonString(gatewayAgentRpcStringParam(request, ["channel"], "gateway-rpc")))
    let prompt = gatewayAgentRpcStringParam(request, ["text", "prompt", "message"], "")
    preview.put("promptChars", Int64(prompt.size).toJsonValue())
    preview.put("preview", JsonString("agent-ready"))
    preview
}

private func gatewayAgentHealthJson(agentId: String): JsonObject {
    let agent = gatewayAgentGetJson(agentId)
    let health = JsonObject()
    let configured = match (agent.get("configured")) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
    let kind = match (agent.get("kind")) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { "unknown" }
        case None => "unknown"
    }
    let actions = JsonArray([])
    let inspect = JsonObject()
    inspect.put("action", JsonString("inspect-agent"))
    inspect.put("method", JsonString("agent.get"))
    let inspectParams = JsonObject()
    inspectParams.put("agentId", JsonString(agentId))
    inspect.put("params", inspectParams)
    actions.add(inspect)
    if (configured) {
        let preview = JsonObject()
        preview.put("action", JsonString("preview-routing"))
        preview.put("method", JsonString("agent.routing"))
        preview.put("params", inspectParams)
        actions.add(preview)
    }
    health.put("agent", agent)
    health.put("healthy", configured.toJsonValue())
    health.put("state", JsonString(if (configured) { "ready" } else { "missing" }))
    health.put("kind", JsonString(kind))
    health.put("actionsNeeded", (!configured).toJsonValue())
    health.put("policyState", JsonString(if (configured) { "routable" } else { "unavailable" }))
    health.put("actions", actions)
    health
}

private func gatewayAgentRoutingJson(agentId: String, request: GatewayRpcRequest): JsonObject {
    let user = CliSettingManager.readGatewaySettings()
    let routing = JsonObject()
    let invokeParams = gatewayAgentResolvedInvokeParams(agentId, request)
    let context = gatewayAgentInvokeContext(agentId, request)
    let channel = gatewayAgentJsonString(invokeParams, "channel", "gateway-rpc")
    let to = gatewayAgentJsonString(invokeParams, "to", "")
    let lane = gatewayAgentJsonString(invokeParams, "lane", "")
    let sessionKey = context.sessionKey
    let prompt = gatewayAgentJsonString(invokeParams, "text", "")
    let thinking = gatewayAgentJsonString(invokeParams, "thinking", "")
    let replyTo = gatewayAgentJsonString(invokeParams, "replyTo", "")
    let replyChannel = gatewayAgentJsonString(invokeParams, "replyChannel", "")
    let replyAccount = gatewayAgentJsonString(invokeParams, "replyAccount", "")
    let replyToMessageId = gatewayAgentJsonString(invokeParams, "replyToMessageId", "")
    let replyInThread = gatewayAgentJsonBool(invokeParams, "replyInThread", false)
    let verbose = gatewayAgentJsonString(invokeParams, "verbose", "")
    let extraSystemPrompt = gatewayAgentJsonString(invokeParams, "extraSystemPrompt", "")
    let idempotencyKey = gatewayAgentJsonString(invokeParams, "idempotencyKey", "")
    let configured = match (gatewayAgentGetJson(agentId).get("configured")) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
    let actions = JsonArray([])
    let invoke = JsonObject()
    invoke.put("action", JsonString("invoke-agent"))
    invoke.put("method", JsonString("agent.invoke"))
    invoke.put("params", invokeParams)
    actions.add(invoke)
    routing.put("agentId", JsonString(agentId))
    routing.put("channel", JsonString(channel))
    routing.put("sessionKey", JsonString(sessionKey))
    routing.put("to", JsonString(to))
    routing.put("thinking", JsonString(thinking))
    routing.put("lane", JsonString(lane))
    routing.put("replyTo", JsonString(replyTo))
    routing.put("replyChannel", JsonString(replyChannel))
    routing.put("replyAccount", JsonString(replyAccount))
    let deliveryTarget = JsonObject()
    deliveryTarget.put("channel", JsonString(if (!replyChannel.isEmpty()) { replyChannel } else { context.channelName }))
    deliveryTarget.put("peer", JsonString(if (!replyTo.isEmpty()) { replyTo } else { to }))
    deliveryTarget.put("replyChannel", JsonString(if (!replyChannel.isEmpty()) { replyChannel } else { context.channelName }))
    deliveryTarget.put("replyTo", JsonString(if (!replyTo.isEmpty()) { replyTo } else { to }))
    deliveryTarget.put("replyToMessageId", JsonString(replyToMessageId))
    deliveryTarget.put("replyInThread", replyInThread.toJsonValue())
    deliveryTarget.put("accountId", JsonString(replyAccount))
    deliveryTarget.put("deliverable", ((!replyChannel.isEmpty()) || (!to.isEmpty())).toJsonValue())
    let effectiveChannel = if (!replyChannel.isEmpty()) { replyChannel } else { context.channelName }
    routing.put("deliveryTarget", gatewayApplyChannelDeliveryPolicy(user, effectiveChannel, deliveryTarget))
    routing.put("verbose", JsonString(verbose))
    routing.put("extraSystemPrompt", JsonString(extraSystemPrompt))
    routing.put("idempotencyKey", JsonString(idempotencyKey))
    routing.put("transport", JsonString(if (channel == "gateway-rpc") { "rpc" } else { "channel" }))
    routing.put("delivery", JsonString(if (prompt.isEmpty()) { "idle" } else { "invoke" }))
    routing.put("promptChars", Int64(prompt.size).toJsonValue())
    routing.put("routingState", JsonString(if (!configured) { "blocked" } else if (prompt.isEmpty()) { "ready" } else { "queued" }))
    routing.put("policyState", JsonString(if (!configured) { "unavailable" } else if (channel == "gateway-rpc") { "direct-rpc" } else { "channel-routed" }))
    routing.put("actions", actions)
    routing
}

private func gatewayAgentActionsJson(agentId: String, request: GatewayRpcRequest): JsonObject {
    let health = gatewayAgentHealthJson(agentId)
    let routing = gatewayAgentRoutingJson(agentId, request)
    let configured = match (health.get("healthy")) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
    let constraints = JsonArray([])
    let agentPresent = JsonObject()
    agentPresent.put("name", JsonString("agent-configured"))
    agentPresent.put("satisfied", configured.toJsonValue())
    agentPresent.put("detail", JsonString(if (configured) { "agent is configured and routable" } else { "agent is unavailable" }))
    constraints.add(agentPresent)
    let routingReady = JsonObject()
    let delivery = match (routing.get("delivery")) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { "idle" }
        case None => "idle"
    }
    routingReady.put("name", JsonString("routing-ready"))
    routingReady.put("satisfied", (gatewayAgentJsonString(routing, "policyState", "") != "unavailable").toJsonValue())
    routingReady.put("detail", JsonString("delivery=${delivery}"))
    constraints.add(routingReady)
    let actions = JsonArray([])
    match (health.get("actions")) {
        case Some(v) =>
            try {
                for (i in 0..v.asArray().size()) {
                    actions.add(v.asArray()[i])
                }
            } catch (_e: Exception) {
                ()
            }
        case None => ()
    }
    match (routing.get("actions")) {
        case Some(v) =>
            try {
                for (i in 0..v.asArray().size()) {
                    actions.add(v.asArray()[i])
                }
            } catch (_e: Exception) {
                ()
            }
        case None => ()
    }
    let result = JsonObject()
    result.put("agent", gatewayAgentGetJson(agentId))
    result.put("health", health)
    result.put("routing", routing)
    result.put("policyState", JsonString(if (configured) { gatewayAgentJsonString(routing, "policyState", "routable") } else { "unavailable" }))
    result.put("remediationState", JsonString(if (configured) { "ready" } else { "agent-required" }))
    result.put("actionsNeeded", (!configured || delivery == "idle").toJsonValue())
    result.put("constraints", constraints)
    result.put("actions", actions)
    result
}

private func gatewayAgentsHealthJson(): JsonObject {
    let result = JsonObject()
    let builtin = gatewayBuiltinAgentsJson()
    let custom = gatewayCustomAgentsJson()
    result.put("builtinCount", builtin.size().toJsonValue())
    result.put("customCount", custom.size().toJsonValue())
    result.put("healthy", (builtin.size() > 0).toJsonValue())
    result
}

private func gatewayAgentsSummaryJson(): JsonObject {
    let builtins = gatewayBuiltinAgentsJson()
    let customs = gatewayCustomAgentsJson()
    let summary = JsonObject()
    summary.put("builtinCount", builtins.size().toJsonValue())
    summary.put("customCount", customs.size().toJsonValue())
    summary.put("totalCount", Int64(builtins.size() + customs.size()).toJsonValue())
    summary.put("healthy", (builtins.size() > 0).toJsonValue())
    let contract = gatewayAgentsContractJson()
    summary.put("defaultId", contract.get("defaultId") ?? JsonString("main"))
    summary.put("mainKey", contract.get("mainKey") ?? JsonString("main"))
    summary.put("scope", contract.get("scope") ?? JsonString("global"))
    summary.put("agents", contract.get("agents") ?? JsonArray([]))
    summary
}

public func gatewayResolveAgentScopeFromRoot(
    root: JsonObject,
    agentId!: String = "",
    homeRoot!: Path = MetisPaths.homeRootReadOnly(),
    defaultWorkspace!: Path = MetisPaths.workspaceRootReadOnly()
): JsonObject {
    MetisAgentScope.resolve(root, agentId: agentId, homeRoot: homeRoot, defaultWorkspace: defaultWorkspace)
}

public func gatewayResolveAgentsScopeSummaryFromRoot(
    root: JsonObject,
    homeRoot!: Path = MetisPaths.homeRootReadOnly(),
    defaultWorkspace!: Path = MetisPaths.workspaceRootReadOnly()
): JsonObject {
    MetisAgentScope.summary(root, homeRoot: homeRoot, defaultWorkspace: defaultWorkspace)
}

public func gatewayResolveDefaultAgentScopeFromRoot(
    root: JsonObject,
    homeRoot!: Path = MetisPaths.homeRootReadOnly(),
    defaultWorkspace!: Path = MetisPaths.workspaceRootReadOnly()
): JsonObject {
    let summary = gatewayResolveAgentsScopeSummaryFromRoot(root, homeRoot: homeRoot, defaultWorkspace: defaultWorkspace)
    let defaultId = gatewayAgentJsonString(summary, "defaultAgentId", "main")
    gatewayResolveAgentScopeFromRoot(root, agentId: defaultId, homeRoot: homeRoot, defaultWorkspace: defaultWorkspace)
}

private func gatewayAgentScopeJson(request: GatewayRpcRequest): JsonObject {
    let root = gatewayAgentScopeRootFromRequest(request)
    let agentId = gatewayAgentRpcStringParam(request, ["id", "agent", "agentId"], "")
    let homeRoot = gatewayAgentScopePathParam(request, "homeRoot", MetisPaths.homeRootReadOnly())
    let defaultWorkspace = gatewayAgentScopePathParam(request, "defaultWorkspace", MetisPaths.workspaceRootReadOnly())
    gatewayResolveAgentScopeFromRoot(root, agentId: agentId, homeRoot: homeRoot, defaultWorkspace: defaultWorkspace)
}

private func gatewayDefaultAgentIdReadOnly(): String {
    let summary = MetisAgentScope.summary(
        gatewayAgentConfigRootCloneReadOnly(),
        homeRoot: MetisPaths.homeRootReadOnly(),
        defaultWorkspace: MetisPaths.workspaceRootReadOnly()
    )
    gatewayAgentJsonString(summary, "defaultAgentId", "main")
}

private func gatewayResolveRequestAgentId(request: GatewayRpcRequest): String {
    let requested = gatewayAgentRpcStringParam(request, ["id", "agent", "agentId"], "")
    let scope = MetisAgentScope.resolve(
        gatewayAgentConfigRootCloneReadOnly(),
        agentId: requested,
        homeRoot: MetisPaths.homeRootReadOnly(),
        defaultWorkspace: MetisPaths.workspaceRootReadOnly()
    )
    gatewayAgentJsonString(scope, "agentId", if (requested.trimAscii().isEmpty()) { gatewayDefaultAgentIdReadOnly() } else { requested.trimAscii() })
}

private func gatewayAgentsScopeSummaryJson(request: GatewayRpcRequest): JsonObject {
    let homeRoot = gatewayAgentScopePathParam(request, "homeRoot", MetisPaths.homeRootReadOnly())
    let defaultWorkspace = gatewayAgentScopePathParam(request, "defaultWorkspace", MetisPaths.workspaceRootReadOnly())
    gatewayResolveAgentsScopeSummaryFromRoot(gatewayAgentScopeRootFromRequest(request), homeRoot: homeRoot, defaultWorkspace: defaultWorkspace)
}

private func gatewayAgentsDefaultScopeJson(request: GatewayRpcRequest): JsonObject {
    let homeRoot = gatewayAgentScopePathParam(request, "homeRoot", MetisPaths.homeRootReadOnly())
    let defaultWorkspace = gatewayAgentScopePathParam(request, "defaultWorkspace", MetisPaths.workspaceRootReadOnly())
    gatewayResolveDefaultAgentScopeFromRoot(gatewayAgentScopeRootFromRequest(request), homeRoot: homeRoot, defaultWorkspace: defaultWorkspace)
}

public func handleGatewayAgentsFamily(method: String, request!: Option<GatewayRpcRequest> = None): Option<GatewayRpcResponse> {
    if (method == "agents.list" || method == "agents.status") {
        let result = JsonObject()
        let contract = gatewayAgentsContractJson()
        result.put("defaultId", contract.get("defaultId") ?? JsonString("main"))
        result.put("mainKey", contract.get("mainKey") ?? JsonString("main"))
        result.put("scope", contract.get("scope") ?? JsonString("global"))
        result.put("agents", contract.get("agents") ?? JsonArray([]))
        result.put("builtin", gatewayBuiltinAgentsJson())
        result.put("custom", gatewayCustomAgentsJson())
        result.put("health", gatewayAgentsHealthJson())
        result.put("summary", gatewayAgentsSummaryJson())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "agents.health") {
        let result = JsonObject()
        result.put("agents", gatewayAgentsHealthJson())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "agents.summary") {
        let result = JsonObject()
        result.put("agents", gatewayAgentsSummaryJson())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "agents.scope") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let result = JsonObject()
        result.put("scope", gatewayAgentsScopeSummaryJson(requestValue))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "agents.default") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let result = JsonObject()
        result.put("scope", gatewayAgentsDefaultScopeJson(requestValue))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "agents.capabilities") {
        let result = JsonObject()
        let rows = JsonArray([])
        for (name in ["main", "cangjie", "explorer", "editor", "reviewer", "test_generator", "refactoring", "planner"]) {
            let row = JsonObject()
            row.put("id", JsonString(name))
            row.put("capabilities", gatewayBuiltinAgentCapabilities(name))
            rows.add(row)
        }
        result.put("agents", rows)
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "agents.runtime" || method == "agents.runtime.profile") {
        let result = JsonObject()
        result.put("runtime", gatewayMainRuntimeProfileJson())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "agents.runtime.audit") {
        let result = JsonObject()
        result.put("audit", gatewayMainRuntimeAuditJson())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "agents.bindings") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        return Some(GatewayRpcResponse(true, method, result: gatewayAgentBindingsListJson(requestValue)))
    }
    if (method == "agents.bind") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let response = gatewayAgentBindingsApplyJson(requestValue)
        return Some(GatewayRpcResponse(response.ok, method, result: response.result, error: response.error))
    }
    if (method == "agents.unbind") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let response = gatewayAgentBindingsRemoveJson(requestValue)
        return Some(GatewayRpcResponse(response.ok, method, result: response.result, error: response.error))
    }
    if (method == "agents.add") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let response = gatewayAgentAddJson(requestValue)
        return Some(GatewayRpcResponse(response.ok, method, result: response.result, error: response.error))
    }
    if (method == "agents.set-identity") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let response = gatewayAgentSetIdentityJson(requestValue)
        return Some(GatewayRpcResponse(response.ok, method, result: response.result, error: response.error))
    }
    if (method == "agents.delete") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let response = gatewayAgentDeleteJson(requestValue)
        return Some(GatewayRpcResponse(response.ok, method, result: response.result, error: response.error))
    }
    if (method == "agent.get") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let agentId = gatewayResolveRequestAgentId(requestValue)
        let result = JsonObject()
        result.put("agent", gatewayAgentGetJson(agentId))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "agent.scope") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let result = JsonObject()
        result.put("scope", gatewayAgentScopeJson(requestValue))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "agent.preview") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let agentId = gatewayResolveRequestAgentId(requestValue)
        let result = JsonObject()
        result.put("preview", gatewayAgentPreviewJson(agentId, requestValue))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "agent.health") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let agentId = gatewayResolveRequestAgentId(requestValue)
        let result = JsonObject()
        result.put("health", gatewayAgentHealthJson(agentId))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "agent.routing") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let agentId = gatewayResolveRequestAgentId(requestValue)
        let result = JsonObject()
        result.put("routing", gatewayAgentRoutingJson(agentId, requestValue))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "agent.actions") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let agentId = gatewayResolveRequestAgentId(requestValue)
        let result = JsonObject()
        result.put("actions", gatewayAgentActionsJson(agentId, requestValue))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "agent.invoke") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let agentId = gatewayResolveRequestAgentId(requestValue)
        let params = gatewayAgentResolvedInvokeParams(agentId, requestValue)
        let context = gatewayAgentInvokeContext(agentId, requestValue)
        let invoke = gatewayExecuteChatTurnFromRpc(params, fallbackSource: GatewayIngressSource.GatewayRpc)
        let result = JsonObject()
        result.put("agent", gatewayAgentGetJson(agentId))
        result.put("routing", gatewayAgentRoutingJson(agentId, requestValue))
        result.put("invoke", invoke)
        match (invoke.get("error")) {
            case Some(v) =>
                let err = try { v.asString().getValue() } catch (_e: Exception) { "agent invoke failed" }
                return Some(GatewayRpcResponse(false, method, result: result, error: err))
            case None =>
                return Some(GatewayRpcResponse(true, method, result: result))
        }
    }
    None
}
