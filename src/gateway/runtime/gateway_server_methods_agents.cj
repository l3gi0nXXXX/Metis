package metis.gateway.runtime

import magic.jsonable.*

import metis.core.{gatewayMainRuntimeExtendedToolNames, gatewayMainRuntimeRequiredToolNames, missingRuntimeToolNames, resolveRuntimeToolPolicyFromRoot, runtimeToolPolicyReportToJson}
import metis.core.config.{CliConfig, CliModelRuntimeStateManager, CliModelRuntimeStateRefreshResult, CliSettingManager, MetisAgentScope, MetisConfigManager, MetisPaths, GatewayUserSettings}
import metis.core.memory.MemoryRuntimeRegistry
import metis.core.prompting.{MetisAgentWorkspaceBootstrapResult, ensureMetisAgentWorkspace, metisWorkspaceBootstrapFilenames, metisWorkspaceSafeRead, metisWorkspaceSafeWrite, validateMetisIdentityAvatar}
import metis.core.skills.resolveAgentSkillVisibility
import metis.gateway.config.buildGatewayConfigFromUserSettings
import metis.gateway.core.{GatewayAgentBindingApplyResult, GatewayAgentBindingConflict, GatewayAgentBindingRemoveResult, gatewayAgentTeamMigrationDryRun, gatewayApplyAgentRouteBindings, gatewayAuthorizedChatToolNames, gatewayBuildLegacyAgentRouteBinding, gatewayCorePromptRuntimeCapabilities, gatewayDefaultChatRuntimeHasUnifiedCoreTools, gatewayDefaultChatToolNames, gatewayMainRuntimePromptTemplateId, gatewayMainRuntimePromptVarianceFields, gatewayRemoveAgentRouteBindings, gatewaySanitizeAgentId}
import metis.gateway.session.{GatewayIngressSource, GatewaySessionRequest, gatewayBuildSessionRpcParams, gatewayIngressSourceFromString, gatewayResolveSessionContext, gatewaySessionRequestFromRpcParams}

import std.collection.{ArrayList, HashMap}
import std.convert.Parsable
import std.fs.{Directory, File, FileInfo, Path, copy, exists, remove}
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

private func gatewayAgentRpcRawStringParam(request: GatewayRpcRequest, keys: Array<String>, defaultValue: String): String {
    for (key in keys) {
        match (request.params.get(key)) {
            case Some(v) =>
                try {
                    return v.asString().getValue()
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

private func gatewayAgentRequestHasAny(request: GatewayRpcRequest, keys: Array<String>): Bool {
    for (key in keys) {
        if (request.params.get(key).isSome()) {
            return true
        }
    }
    false
}

private func gatewayAgentCloneValue(value: JsonValue): JsonValue {
    try {
        JsonValue.fromStr(value.toJsonString())
    } catch (_e: Exception) {
        value
    }
}

private func gatewayAgentCloneObject(obj: JsonObject): JsonObject {
    try {
        JsonValue.fromStr(obj.toJsonString()).asObject()
    } catch (_e: Exception) {
        JsonObject()
    }
}

private func gatewayAgentCloneArray(arr: JsonArray): JsonArray {
    try {
        JsonValue.fromStr(arr.toJsonString()).asArray()
    } catch (_e: Exception) {
        JsonArray([])
    }
}

private func gatewayAgentJsonArray(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func gatewayAgentJsonObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
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

private func gatewayAgentPutModelJson(out: JsonObject, entry: JsonObject): Unit {
    match (entry.get("model")) {
        case Some(v) =>
            try {
                out.put("model", gatewayAgentCloneObject(v.asObject()))
                return
            } catch (_e: Exception) {
                ()
            }
            try {
                let model = v.asString().getValue().trimAscii()
                let modelJson = gatewayAgentSummaryModelJson(model)
                if (modelJson.size() > 0) {
                    out.put("model", modelJson)
                }
            } catch (_e: Exception) {
                ()
            }
        case None => ()
    }
}

private func gatewayAgentAliasArrayFromGroupChat(groupChat: JsonObject): JsonArray {
    let out = JsonArray([])
    let seen = ArrayList<String>()
    let mentionPatterns = gatewayAgentJsonArray(groupChat, "mentionPatterns")
    for (i in 0..mentionPatterns.size()) {
        let alias = try { mentionPatterns[i].asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        if (!alias.isEmpty() && !seen.contains(alias)) {
            out.add(JsonString(alias))
            seen.add(alias)
        }
    }
    out
}

private func gatewayAgentPutGroupChatAndAliases(out: JsonObject, entry: JsonObject): Unit {
    match (entry.get("groupChat")) {
        case Some(v) =>
            try {
                let groupChat = gatewayAgentCloneObject(v.asObject())
                out.put("groupChat", groupChat)
                let aliases = gatewayAgentAliasArrayFromGroupChat(groupChat)
                if (aliases.size() > 0) {
                    out.put("aliases", aliases)
                }
            } catch (_e: Exception) {
                ()
            }
        case None => ()
    }
}

private func gatewayAgentTeamsList(root: JsonObject): JsonArray {
    match (root.get("agentTeams")) {
        case Some(v) =>
            try {
                let teams = v.asObject()
                match (teams.get("list")) {
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

private func gatewayAgentTeamsWriteList(root: JsonObject, teamsList: JsonArray): Unit {
    let teams = match (root.get("agentTeams")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    teams.put("list", teamsList)
    root.put("agentTeams", teams)
}

private func gatewayAgentTeamIdsForAgent(root: JsonObject, agentId: String): JsonArray {
    let normalized = gatewaySanitizeAgentId(agentId)
    let out = JsonArray([])
    let seen = ArrayList<String>()
    let teams = gatewayAgentTeamsList(root)
    for (i in 0..teams.size()) {
        let team = try { teams[i].asObject() } catch (_e: Exception) { JsonObject() }
        let teamId = gatewaySanitizeAgentId(gatewayAgentJsonString(team, "id", ""))
        if (teamId.isEmpty()) {
            continue
        }
        var matched = false
        let members = gatewayAgentJsonArray(team, "members")
        for (j in 0..members.size()) {
            let memberAgentId = try {
                gatewaySanitizeAgentId(members[j].asObject().get("agentId").getOrThrow().asString().getValue())
            } catch (_e: Exception) {
                try { gatewaySanitizeAgentId(members[j].asString().getValue()) } catch (_e2: Exception) { "" }
            }
            if (memberAgentId == normalized) {
                matched = true
                break
            }
        }
        if (!matched) {
            let aliases = gatewayAgentJsonArray(team, "aliases")
            for (j in 0..aliases.size()) {
                let aliasObj = try { aliases[j].asObject() } catch (_e: Exception) { JsonObject() }
                if (gatewaySanitizeAgentId(gatewayAgentJsonString(aliasObj, "agentId", "")) == normalized) {
                    matched = true
                    break
                }
            }
        }
        if (matched && !seen.contains(teamId)) {
            out.add(JsonString(teamId))
            seen.add(teamId)
        }
    }
    out
}

private func gatewayAgentArrayContains(items: ArrayList<String>, value: String): Bool {
    for (item in items) {
        if (item == value) {
            return true
        }
    }
    false
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

private func gatewayAgentStringArrayJson(values: Array<String>): JsonArray {
    let arr = JsonArray([])
    for (value in values) {
        arr.add(JsonString(value))
    }
    arr
}

private func gatewayAgentRuntimePolicyRoot(user: GatewayUserSettings): JsonObject {
    let root = gatewayAgentConfigRootClone()
    let gatewayObj = match (root.get("gateway")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let toolsObj = JsonObject()
    if (user.tools.allow.size > 0) {
        toolsObj.put("allow", gatewayAgentStringArrayJson(user.tools.allow))
    }
    if (user.tools.deny.size > 0) {
        toolsObj.put("deny", gatewayAgentStringArrayJson(user.tools.deny))
    }
    if (toolsObj.size() > 0) {
        gatewayObj.put("tools", toolsObj)
        root.put("gateway", gatewayObj)
    }
    root
}

private func gatewayAgentToolsJson(agentId: String, currentNames: Array<String>): JsonObject {
    runtimeToolPolicyReportToJson(
        resolveRuntimeToolPolicyFromRoot(
            gatewayAgentRuntimePolicyRoot(CliSettingManager.readGatewaySettings()),
            currentNames,
            agentId: agentId
        )
    )
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
    authorizationProfile.put(
        "effectivePolicy",
        runtimeToolPolicyReportToJson(resolveRuntimeToolPolicyFromRoot(gatewayAgentRuntimePolicyRoot(gatewayUser), currentNames))
    )
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

private func gatewayAgentSummaryRow(agentId: String, kind: String, entry!: JsonObject = JsonObject(), root!: JsonObject = JsonObject()): JsonObject {
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
    let configuredAgentDir = gatewayAgentJsonString(entry, "agentDir", "").trimAscii()
    if (!configuredAgentDir.isEmpty()) {
        row.put("agentDir", JsonString(configuredAgentDir))
    }
    let configuredSessionsDir = gatewayAgentJsonString(entry, "sessionsDir", "").trimAscii()
    if (!configuredSessionsDir.isEmpty()) {
        row.put("sessionsDir", JsonString(configuredSessionsDir))
    }
    gatewayAgentPutModelJson(row, entry)
    gatewayAgentPutGroupChatAndAliases(row, entry)
    let teamIds = gatewayAgentTeamIdsForAgent(root, normalized)
    if (teamIds.size() > 0) {
        row.put("teamIds", teamIds)
    }
    row.put("skills", gatewayAgentSkillsJson(normalized))
    row.put("tools", gatewayAgentToolsJson(normalized, gatewayDefaultChatToolNames()))
    row.put("kind", JsonString(kind))
    row
}

private func gatewayAgentAppendCustomSummaryRow(rows: JsonArray, seen: ArrayList<String>, agentId: String, entry: JsonObject, root!: JsonObject = JsonObject()): Unit {
    let normalized = gatewaySanitizeAgentId(agentId)
    if (normalized.isEmpty() || gatewayAgentArrayContains(seen, normalized)) {
        return
    }
    rows.add(gatewayAgentSummaryRow(normalized, "custom", entry: entry, root: root))
    seen.add(normalized)
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
    let seenCustom = ArrayList<String>()
    let entries = gatewayAgentConfigEntries(root)
    for (i in 0..entries.size()) {
        let entry = try { entries[i].asObject() } catch (_e: Exception) { JsonObject() }
        let agentId = gatewayAgentJsonString(entry, "id", "")
        let agentDirText = gatewayAgentJsonString(entry, "agentDir", "")
        if (agentId.trimAscii().isEmpty() || agentDirText.trimAscii().isEmpty()) {
            continue
        }
        if (exists(Path(agentDirText).join("AGENT.md"))) {
            gatewayAgentAppendCustomSummaryRow(agents, seenCustom, agentId, entry, root: root)
        }
    }
    for (agentDir in CliConfig.subagentDirs) {
        if (!exists(agentDir)) {
            continue
        }
        let directManifest = agentDir.join("AGENT.md")
        if (exists(directManifest)) {
            let agentId = agentDir.fileName
            let configuredEntry = gatewayAgentConfigEntry(root, agentId)
            gatewayAgentAppendCustomSummaryRow(agents, seenCustom, agentId, configuredEntry, root: root)
            continue
        }
        let nestedManifest = agentDir.join("agent").join("AGENT.md")
        if (exists(nestedManifest)) {
            let agentId = agentDir.fileName
            let configuredEntry = gatewayAgentConfigEntry(root, agentId)
            gatewayAgentAppendCustomSummaryRow(agents, seenCustom, agentId, configuredEntry, root: root)
            continue
        }
        for (entry in Directory.readFrom(agentDir)) {
            if (!entry.isDirectory()) {
                continue
            }
            if (entry.name == "agent") {
                continue
            }
            let manifest = agentDir.join(entry.name).join("AGENT.md")
            if (!exists(manifest)) {
                continue
            }
            let configuredEntry = gatewayAgentConfigEntry(root, entry.name)
            gatewayAgentAppendCustomSummaryRow(agents, seenCustom, entry.name, configuredEntry, root: root)
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

private class GatewayAgentAuthProfileCopyPlan {
    public var requested: Bool = false
    public var ok: Bool = true
    public var error: String = ""
    public var sourcePath: String = ""
    public var targetPath: String = ""
    public init() {}
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

private func gatewayAgentResolveAuthProfileSource(source: String): String {
    let normalized = source.trimAscii()
    if (normalized.isEmpty()) {
        return ""
    }
    let low = normalized.toAsciiLower()
    if (low == "default-agent") {
        return MetisPaths.homeRoot().join("auth-profiles.json").toString()
    }
    ""
}

private func gatewayAgentAuthProfileCopyPlan(request: GatewayRpcRequest, targetAgentDir: Path): GatewayAgentAuthProfileCopyPlan {
    let plan = GatewayAgentAuthProfileCopyPlan()
    plan.requested = gatewayAgentJsonBool(request.params, "copyAuthProfiles", false) ||
        gatewayAgentJsonBool(request.params, "importAuthProfiles", false)
    plan.targetPath = targetAgentDir.join("auth-profiles.json").toString()
    if (!plan.requested) {
        return plan
    }
    let confirmed = gatewayAgentJsonBool(request.params, "confirm", false) || gatewayAgentJsonBool(request.params, "force", false)
    if (!confirmed) {
        plan.ok = false
        plan.error = "Auth profile copy/import requires confirm=true or force=true."
        return plan
    }
    let source = gatewayAgentRpcStringParam(
        request,
        ["source", "authProfilesSource"],
        ""
    )
    if (source.trimAscii().isEmpty() || source.trimAscii().toAsciiLower() != "default-agent") {
        plan.ok = false
        plan.error = "Auth profile copy/import requires source=default-agent."
        return plan
    }
    let sourcePath = gatewayAgentResolveAuthProfileSource(source)
    if (sourcePath.trimAscii().isEmpty() || !exists(Path(sourcePath))) {
        plan.ok = false
        plan.error = "Auth profile source not found."
        return plan
    }
    if (exists(Path(plan.targetPath))) {
        plan.ok = false
        plan.error = "Target auth-profiles.json already exists; refusing to overwrite."
        return plan
    }
    plan.sourcePath = sourcePath
    plan
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

private func gatewayAgentBindingPeer(matchObj: JsonObject): JsonObject {
    match (matchObj.get("peer")) {
        case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func gatewayAgentBindingDescribe(binding: JsonObject): String {
    let matchObj = match (binding.get("match")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let channel = gatewayAgentJsonString(matchObj, "channel", "")
    let accountId = gatewayAgentJsonString(matchObj, "accountId", "")
    var out = if (accountId.trimAscii().isEmpty()) {
        channel
    } else {
        "${channel}:${accountId.trimAscii()}"
    }
    let peer = gatewayAgentBindingPeer(matchObj)
    if (peer.size() > 0) {
        out += " peer=${gatewayAgentJsonString(peer, "kind", "")}:${gatewayAgentJsonString(peer, "id", "")}"
    }
    let guildId = gatewayAgentJsonString(matchObj, "guildId", "")
    if (!guildId.isEmpty()) {
        out += " guild=${guildId}"
    }
    let teamId = gatewayAgentJsonString(matchObj, "teamId", "")
    if (!teamId.isEmpty()) {
        out += " team=${teamId}"
    }
    out
}

private func gatewayAgentRouteBindingHasChannel(binding: JsonObject): Bool {
    let matchObj = gatewayAgentJsonObject(binding, "match")
    !gatewayAgentJsonString(matchObj, "channel", "").trimAscii().isEmpty()
}

private func gatewayAgentAppendLegacyBindingSpec(bindings: JsonArray, errors: JsonArray, agentId: String, spec: String): Unit {
    let trimmed = spec.trimAscii()
    if (trimmed.isEmpty()) {
        return
    }
    let binding = gatewayBuildLegacyAgentRouteBinding(agentId, trimmed)
    if (!gatewayAgentRouteBindingHasChannel(binding)) {
        errors.add(JsonString("Invalid binding spec: ${trimmed}"))
        return
    }
    bindings.add(binding)
}

private func gatewayAgentAppendLegacyBindingValue(bindings: JsonArray, errors: JsonArray, agentId: String, value: JsonValue): Unit {
    try {
        let arr = value.asArray()
        for (i in 0..arr.size()) {
            try {
                gatewayAgentAppendLegacyBindingSpec(bindings, errors, agentId, arr[i].asString().getValue())
            } catch (_inner: Exception) {
                errors.add(JsonString("Binding spec must be a string."))
            }
        }
        return
    } catch (_e: Exception) {
        ()
    }
    try {
        gatewayAgentAppendLegacyBindingSpec(bindings, errors, agentId, value.asString().getValue())
    } catch (_inner: Exception) {
        errors.add(JsonString("Binding spec must be a string or string array."))
    }
}

private func gatewayAgentBuildRouteBindingFromObject(defaultAgentId: String, source: JsonObject, requireDefaultAgent!: Bool): (JsonObject, String) {
    let explicitAgentId = gatewaySanitizeAgentId(gatewayAgentJsonString(source, "agentId", ""))
    let targetAgentId = if (explicitAgentId.isEmpty()) { defaultAgentId } else { explicitAgentId }
    if (targetAgentId.isEmpty()) {
        return (JsonObject(), "Binding agentId is required.")
    }
    if (requireDefaultAgent && explicitAgentId != "" && explicitAgentId != defaultAgentId) {
        return (JsonObject(), "Binding agentId \"${explicitAgentId}\" must match request agent \"${defaultAgentId}\".")
    }

    let matchObj = match (source.get("match")) {
        case Some(v) => try { gatewayAgentCloneObject(v.asObject()) } catch (_e: Exception) { JsonObject() }
        case None =>
            let legacyMatch = JsonObject()
            for (key in ["channel", "accountId", "guildId", "teamId", "roles", "peer"]) {
                match (source.get(key)) {
                    case Some(v) => legacyMatch.put(key, gatewayAgentCloneValue(v))
                    case None => ()
                }
            }
            legacyMatch
    }
    if (gatewayAgentJsonString(matchObj, "channel", "").trimAscii().isEmpty()) {
        return (JsonObject(), "Route binding match.channel is required.")
    }

    let binding = JsonObject()
    binding.put("type", JsonString("route"))
    binding.put("agentId", JsonString(targetAgentId))
    binding.put("match", matchObj)
    match (source.get("enabled")) {
        case Some(v) => binding.put("enabled", gatewayAgentCloneValue(v))
        case None => ()
    }
    match (source.get("comment")) {
        case Some(v) => binding.put("comment", gatewayAgentCloneValue(v))
        case None => ()
    }
    (binding, "")
}

private func gatewayAgentAppendRouteBindingValue(bindings: JsonArray, errors: JsonArray, defaultAgentId: String, value: JsonValue, requireDefaultAgent!: Bool): Unit {
    try {
        let text = value.asString().getValue()
        gatewayAgentAppendLegacyBindingSpec(bindings, errors, defaultAgentId, text)
        return
    } catch (_e: Exception) {
        ()
    }
    try {
        let obj = value.asObject()
        let (binding, error) = gatewayAgentBuildRouteBindingFromObject(defaultAgentId, obj, requireDefaultAgent: requireDefaultAgent)
        if (!error.isEmpty()) {
            errors.add(JsonString(error))
            return
        }
        bindings.add(binding)
        return
    } catch (_e: Exception) {
        ()
    }
    errors.add(JsonString("Binding must be a string or route object."))
}

private func gatewayAgentAppendRouteBindingsParam(bindings: JsonArray, errors: JsonArray, defaultAgentId: String, value: JsonValue, requireDefaultAgent!: Bool): Unit {
    try {
        let arr = value.asArray()
        for (i in 0..arr.size()) {
            gatewayAgentAppendRouteBindingValue(bindings, errors, defaultAgentId, arr[i], requireDefaultAgent: requireDefaultAgent)
        }
        return
    } catch (_e: Exception) {
        ()
    }
    gatewayAgentAppendRouteBindingValue(bindings, errors, defaultAgentId, value, requireDefaultAgent: requireDefaultAgent)
}

private func gatewayAgentParseBindingSpecs(agentId: String, request: GatewayRpcRequest): (JsonArray, JsonArray) {
    let bindings = JsonArray([])
    let errors = JsonArray([])
    match (request.params.get("bind")) {
        case Some(v) => gatewayAgentAppendLegacyBindingValue(bindings, errors, agentId, v)
        case None => ()
    }
    match (request.params.get("bindings")) {
        case Some(v) => gatewayAgentAppendRouteBindingsParam(bindings, errors, agentId, v, requireDefaultAgent: true)
        case None => ()
    }
    (bindings, errors)
}

private func gatewayAgentObjectArrayJson(values: Array<JsonObject>): JsonArray {
    let out = JsonArray([])
    for (value in values) {
        out.add(gatewayAgentCloneObject(value))
    }
    out
}

private func gatewayAgentBindingConflictArrayJson(values: Array<GatewayAgentBindingConflict>): JsonArray {
    let out = JsonArray([])
    for (value in values) {
        let row = JsonObject()
        row.put("binding", gatewayAgentCloneObject(value.binding))
        row.put("existingAgentId", JsonString(value.existingAgentId))
        out.add(row)
    }
    out
}

private func gatewayAgentBindingApplyJson(result: GatewayAgentBindingApplyResult): JsonObject {
    let out = JsonObject()
    out.put("added", gatewayAgentObjectArrayJson(result.added))
    out.put("updated", gatewayAgentObjectArrayJson(result.updated))
    out.put("skipped", gatewayAgentObjectArrayJson(result.skipped))
    out.put("conflicts", gatewayAgentBindingConflictArrayJson(result.conflicts))
    out.put("bindings", gatewayAgentConfigBindings(result.config))
    out.put("configPreview", gatewayAgentCloneObject(result.config))
    out
}

private func gatewayAgentEmptyBindingApplyJson(root: JsonObject): JsonObject {
    let out = JsonObject()
    out.put("added", JsonArray([]))
    out.put("updated", JsonArray([]))
    out.put("skipped", JsonArray([]))
    out.put("conflicts", JsonArray([]))
    out.put("bindings", gatewayAgentConfigBindings(root))
    out.put("configPreview", gatewayAgentCloneObject(root))
    out
}

private func gatewayAgentBindingRemoveJson(result: GatewayAgentBindingRemoveResult): JsonObject {
    let out = JsonObject()
    out.put("removed", gatewayAgentObjectArrayJson(result.removed))
    out.put("missing", gatewayAgentObjectArrayJson(result.missing))
    out.put("conflicts", gatewayAgentBindingConflictArrayJson(result.conflicts))
    out.put("bindings", gatewayAgentConfigBindings(result.config))
    out.put("configPreview", gatewayAgentCloneObject(result.config))
    out
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
    let applyResult = gatewayApplyAgentRouteBindings(root, incoming)
    if (applyResult.added.size > 0 || applyResult.updated.size > 0) {
        MetisConfigManager.writeRoot(applyResult.config)
    }
    let result = gatewayAgentBindingApplyJson(applyResult)
    result.put("agentId", JsonString(agentId))
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
    let removeResult = if (removeAll) {
        let allForAgent = JsonArray([])
        let existing = gatewayAgentConfigBindings(root)
        for (i in 0..existing.size()) {
            let current = try { existing[i].asObject() } catch (_e: Exception) { JsonObject() }
            if (gatewaySanitizeAgentId(gatewayAgentJsonString(current, "agentId", "")) == agentId) {
                allForAgent.add(current)
            }
        }
        gatewayRemoveAgentRouteBindings(root, allForAgent)
    } else {
        gatewayRemoveAgentRouteBindings(root, incoming)
    }
    if (removeResult.removed.size > 0) {
        MetisConfigManager.writeRoot(removeResult.config)
    }
    let result = gatewayAgentBindingRemoveJson(removeResult)
    result.put("agentId", JsonString(agentId))
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
    let agentDirPath = Path(agentDir)
    let workspacePath = Path(workspace)
    let sessionsDirPath = Path(sessionsDir)
    let authCopy = gatewayAgentAuthProfileCopyPlan(request, agentDirPath)
    if (!authCopy.ok) {
        return GatewayRpcResponse(false, "agents.add", error: authCopy.error)
    }
    if (!exists(agentDirPath)) {
        Directory.create(agentDirPath, recursive: true)
    }
    if (!exists(sessionsDirPath)) {
        Directory.create(sessionsDirPath, recursive: true)
    }
    let bootstrap = ensureMetisAgentWorkspace(workspacePath)
    var authProfilesCopied = false
    if (authCopy.requested) {
        copy(Path(authCopy.sourcePath), to: Path(authCopy.targetPath), overwrite: false)
        authProfilesCopied = true
    }
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
    bootstrapJson.put("authProfilesCopied", authProfilesCopied.toJsonValue())
    bootstrapJson.put("authProfilesCopyRequiresExplicitRequest", true.toJsonValue())
    bootstrapJson.put("authProfilesPath", JsonString(agentDirPath.join("auth-profiles.json").toString()))
    bootstrapJson.put("modelsJsonPath", JsonString(agentDirPath.join("models.json").toString()))
    result.put("bootstrap", bootstrapJson)
    GatewayRpcResponse(true, "agents.add", result: result)
}

private func gatewayAgentPutRequestString(entry: JsonObject, request: GatewayRpcRequest, keys: Array<String>, field: String): Unit {
    if (!gatewayAgentRequestHasAny(request, keys)) {
        return
    }
    let value = gatewayAgentRpcStringParam(request, keys, "").trimAscii()
    if (!value.isEmpty()) {
        entry.put(field, JsonString(value))
    }
}

private func gatewayAgentValidateIdentityForWorkspace(workspace: String, identity: JsonObject): String {
    let avatar = gatewayAgentJsonString(identity, "avatar", "").trimAscii()
    if (avatar.isEmpty()) {
        return ""
    }
    let validation = validateMetisIdentityAvatar(Path(workspace), avatar)
    if (!validation.ok) {
        return "Invalid avatar: ${validation.reason}"
    }
    ""
}

private func gatewayAgentPutIdentityFromRequest(entry: JsonObject, request: GatewayRpcRequest, workspace: String): String {
    var identity = match (entry.get("identity")) {
        case Some(v) =>
            try { gatewayAgentCloneObject(v.asObject()) } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    match (request.params.get("identity")) {
        case Some(v) =>
            try {
                identity = gatewayAgentCloneObject(v.asObject())
            } catch (_e: Exception) {
                return "identity must be a JSON object."
            }
        case None => ()
    }
    for (field in ["name", "emoji", "theme", "avatar"]) {
        let value = gatewayAgentRpcStringParam(request, [field], "").trimAscii()
        if (!value.isEmpty()) {
            identity.put(field, JsonString(value))
        }
    }
    let validationError = gatewayAgentValidateIdentityForWorkspace(workspace, identity)
    if (!validationError.isEmpty()) {
        return validationError
    }
    if (identity.size() > 0) {
        entry.put("identity", identity)
    }
    ""
}

private func gatewayAgentPutModelFromRequest(entry: JsonObject, request: GatewayRpcRequest): String {
    match (request.params.get("model")) {
        case Some(v) =>
            try {
                entry.put("model", gatewayAgentCloneObject(v.asObject()))
                return ""
            } catch (_e: Exception) {
                ()
            }
            try {
                let model = v.asString().getValue().trimAscii()
                if (!model.isEmpty()) {
                    entry.put("model", JsonString(model))
                }
                return ""
            } catch (_e: Exception) {
                return "model must be a string or JSON object."
            }
        case None => ""
    }
}

private func gatewayAgentPutGroupChatFromRequest(entry: JsonObject, request: GatewayRpcRequest): String {
    match (request.params.get("groupChat")) {
        case Some(v) =>
            try {
                entry.put("groupChat", gatewayAgentCloneObject(v.asObject()))
                ""
            } catch (_e: Exception) {
                "groupChat must be a JSON object."
            }
        case None => ""
    }
}

private func gatewayAgentUpdateJson(request: GatewayRpcRequest): GatewayRpcResponse {
    let root = gatewayAgentConfigRootClone()
    let agentId = gatewaySanitizeAgentId(gatewayAgentRpcStringParam(request, ["id", "agent", "agentId"], ""))
    if (agentId.isEmpty()) {
        return GatewayRpcResponse(false, "agents.update", error: "Agent id is required.")
    }
    let entries = gatewayAgentConfigEntries(root)
    let index = gatewayAgentConfigFindEntryIndex(entries, agentId)
    if (index < 0) {
        return GatewayRpcResponse(false, "agents.update", error: "Agent \"${agentId}\" not found.")
    }
    let existing = try { entries[index].asObject() } catch (_e: Exception) { JsonObject() }
    let updated = gatewayAgentCloneObject(existing)
    let shouldRefreshModels = gatewayAgentRequestHasAny(request, ["model", "workspace", "agentDir"])
    gatewayAgentPutRequestString(updated, request, ["name"], "name")
    gatewayAgentPutRequestString(updated, request, ["workspace"], "workspace")
    gatewayAgentPutRequestString(updated, request, ["agentDir"], "agentDir")
    gatewayAgentPutRequestString(updated, request, ["sessionsDir"], "sessionsDir")
    let workspace = gatewayAgentJsonString(updated, "workspace", gatewayAgentDefaultWorkspaceDir(agentId).toString()).trimAscii()
    let modelError = gatewayAgentPutModelFromRequest(updated, request)
    if (!modelError.isEmpty()) {
        return GatewayRpcResponse(false, "agents.update", error: modelError)
    }
    let groupChatError = gatewayAgentPutGroupChatFromRequest(updated, request)
    if (!groupChatError.isEmpty()) {
        return GatewayRpcResponse(false, "agents.update", error: groupChatError)
    }
    let identityError = gatewayAgentPutIdentityFromRequest(updated, request, workspace)
    if (!identityError.isEmpty()) {
        return GatewayRpcResponse(false, "agents.update", error: identityError)
    }
    let workspacePath = Path(workspace)
    let bootstrap = ensureMetisAgentWorkspace(workspacePath)
    let agentDir = gatewayAgentJsonString(updated, "agentDir", gatewayAgentDefaultAgentDir(agentId).toString())
    let sessionsDir = gatewayAgentJsonString(updated, "sessionsDir", gatewayAgentDefaultSessionsDir(agentId).toString())
    if (!exists(Path(agentDir))) {
        Directory.create(Path(agentDir), recursive: true)
    }
    if (!exists(Path(sessionsDir))) {
        Directory.create(Path(sessionsDir), recursive: true)
    }
    let manifestPath = Path(agentDir).join("AGENT.md")
    if (!exists(manifestPath)) {
        File.writeTo(
            manifestPath,
            gatewayAgentBuildDefaultManifest(agentId, gatewayAgentJsonString(updated, "name", agentId), workspace).toArray()
        )
    }
    let nextEntries = JsonArray([])
    for (i in 0..entries.size()) {
        if (i == index) {
            nextEntries.add(updated)
        } else {
            nextEntries.add(entries[i])
        }
    }
    gatewayAgentConfigWriteEntries(root, nextEntries)
    MetisConfigManager.writeRoot(root)
    let result = JsonObject()
    result.put("agentId", JsonString(agentId))
    result.put("agent", gatewayAgentGetJson(agentId))
    if (shouldRefreshModels) {
        let scope = MetisAgentScope.resolve(
            root,
            agentId: agentId,
            homeRoot: MetisPaths.homeRootReadOnly(),
            defaultWorkspace: MetisPaths.workspaceRootReadOnly()
        )
        result.put("modelsRefresh", gatewayAgentModelsRefreshResultJson(
            CliModelRuntimeStateManager.refreshAgentRuntimeStateForScope(Path(agentDir), scope)
        ))
    }
    let bootstrapJson = JsonObject()
    bootstrapJson.put("workspaceDir", JsonString(bootstrap.workspaceDir))
    bootstrapJson.put("createdCount", bootstrap.createdCount.toJsonValue())
    bootstrapJson.put("files", gatewayAgentBootstrapFilesJson(bootstrap))
    result.put("bootstrap", bootstrapJson)
    GatewayRpcResponse(true, "agents.update", result: result)
}

private func gatewayAgentScopeForManagementRequest(request: GatewayRpcRequest): (String, JsonObject) {
    let root = gatewayAgentConfigRootCloneReadOnly()
    let agentId = gatewayResolveRequestAgentId(request)
    let scope = MetisAgentScope.resolve(
        root,
        agentId: agentId,
        homeRoot: MetisPaths.homeRootReadOnly(),
        defaultWorkspace: MetisPaths.workspaceRootReadOnly()
    )
    (gatewayAgentJsonString(scope, "agentId", agentId), scope)
}

private func gatewayAgentFileUpdatedAtMillis(path: Path): Int64 {
    if (!exists(path)) {
        return 0
    }
    try {
        FileInfo(path).lastModificationTime.toUnixTimeStamp().toMilliseconds()
    } catch (_e: Exception) {
        0
    }
}

private func gatewayAgentFileSize(path: Path): Int64 {
    if (!exists(path)) {
        return 0
    }
    try {
        FileInfo(path).size
    } catch (_e: Exception) {
        0
    }
}

private func gatewayAgentWorkspaceFileRow(workspace: Path, name: String): JsonObject {
    let path = workspace.join(name)
    let row = JsonObject()
    row.put("name", JsonString(name))
    row.put("path", JsonString(path.toString()))
    row.put("missing", (!exists(path)).toJsonValue())
    row.put("size", gatewayAgentFileSize(path).toJsonValue())
    row.put("updatedAtMs", gatewayAgentFileUpdatedAtMillis(path).toJsonValue())
    row
}

private func gatewayAgentWorkspaceFilesListJson(request: GatewayRpcRequest): GatewayRpcResponse {
    let (agentId, scope) = gatewayAgentScopeForManagementRequest(request)
    if (!gatewayAgentJsonBool(gatewayAgentGetJson(agentId), "configured", false)) {
        return GatewayRpcResponse(false, "agents.files.list", error: "Agent \"${agentId}\" not found.")
    }
    let workspaceText = gatewayAgentJsonString(scope, "workspaceDir", "").trimAscii()
    if (workspaceText.isEmpty()) {
        return GatewayRpcResponse(false, "agents.files.list", error: "Agent workspace is not resolved.")
    }
    let workspace = Path(workspaceText)
    let files = JsonArray([])
    let seen = ArrayList<String>()
    for (name in metisWorkspaceBootstrapFilenames()) {
        files.add(gatewayAgentWorkspaceFileRow(workspace, name))
        seen.add(name)
    }
    if (exists(workspace)) {
        for (entry in Directory.readFrom(workspace)) {
            if (entry.isDirectory()) {
                continue
            }
            let name = entry.name.trimAscii()
            if (name.isEmpty() || seen.contains(name)) {
                continue
            }
            let lower = name.toAsciiLower()
            if (!(lower.endsWith(".md") || lower.endsWith(".txt") || lower.endsWith(".json"))) {
                continue
            }
            files.add(gatewayAgentWorkspaceFileRow(workspace, name))
            seen.add(name)
        }
    }
    let result = JsonObject()
    result.put("agentId", JsonString(agentId))
    result.put("workspace", JsonString(workspaceText))
    result.put("files", files)
    GatewayRpcResponse(true, "agents.files.list", result: result)
}

private func gatewayAgentWorkspaceFileJson(request: GatewayRpcRequest, content!: String = "", includeContent!: Bool = false): GatewayRpcResponse {
    let (agentId, scope) = gatewayAgentScopeForManagementRequest(request)
    if (!gatewayAgentJsonBool(gatewayAgentGetJson(agentId), "configured", false)) {
        return GatewayRpcResponse(false, request.method, error: "Agent \"${agentId}\" not found.")
    }
    let workspaceText = gatewayAgentJsonString(scope, "workspaceDir", "").trimAscii()
    let name = gatewayAgentRpcStringParam(request, ["name", "path"], "").trimAscii()
    if (workspaceText.isEmpty() || name.isEmpty()) {
        return GatewayRpcResponse(false, request.method, error: "Agent workspace and file name are required.")
    }
    let workspace = Path(workspaceText)
    let io = if (includeContent) {
        metisWorkspaceSafeWrite(workspace, name, content)
    } else {
        metisWorkspaceSafeRead(workspace, name)
    }
    if (!io.ok) {
        return GatewayRpcResponse(false, request.method, error: io.reason)
    }
    let file = gatewayAgentWorkspaceFileRow(workspace, name)
    file.put("path", JsonString(io.path))
    file.put("missing", false.toJsonValue())
    file.put("content", JsonString(io.content))
    let result = JsonObject()
    result.put("agentId", JsonString(agentId))
    result.put("workspace", JsonString(workspaceText))
    result.put("file", file)
    GatewayRpcResponse(true, request.method, result: result)
}

private func gatewayAgentSecretKey(key: String): Bool {
    let lower = key.trimAscii().toAsciiLower()
    if (lower.endsWith("configured") || lower.endsWith("status")) {
        return false
    }
    lower.contains("token") || lower.contains("secret") || lower.contains("apikey") ||
        lower.contains("api_key") || lower.contains("password") || lower.contains("authorization")
}

private func gatewayAgentRedactArray(arr: JsonArray): JsonArray {
    let out = JsonArray([])
    for (item in arr.getItems()) {
        try {
            out.add(gatewayAgentRedactObject(item.asObject()))
        } catch (_e: Exception) {
            try {
                out.add(gatewayAgentRedactArray(item.asArray()))
            } catch (_e2: Exception) {
                out.add(gatewayAgentCloneValue(item))
            }
        }
    }
    out
}

private func gatewayAgentRedactObject(obj: JsonObject): JsonObject {
    let out = JsonObject()
    for ((key, value) in obj.getFields()) {
        if (gatewayAgentSecretKey(key)) {
            out.put(key, JsonString("<redacted>"))
            continue
        }
        try {
            out.put(key, gatewayAgentRedactObject(value.asObject()))
        } catch (_e: Exception) {
            try {
                out.put(key, gatewayAgentRedactArray(value.asArray()))
            } catch (_e2: Exception) {
                out.put(key, gatewayAgentCloneValue(value))
            }
        }
    }
    out
}

private func gatewayAgentProviderCount(state: JsonObject): Int64 {
    match (state.get("providers")) {
        case Some(v) =>
            try { return v.asArray().size() } catch (_e: Exception) { () }
            try { return v.asObject().size() } catch (_e2: Exception) { () }
            0
        case None => 0
    }
}

private func gatewayAgentModelsReadState(path: Path, diagnostics: JsonArray): JsonObject {
    if (!exists(path)) {
        return JsonObject()
    }
    try {
        JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject()
    } catch (e: Exception) {
        diagnostics.add(JsonString("invalid models.json: ${e.message}"))
        JsonObject()
    }
}

private func gatewayAgentModelsResponse(agentId: String, agentDir: Path, path: Path, state: JsonObject,
    diagnostics: JsonArray, credentialSource: JsonObject): JsonObject {
    let models = JsonObject()
    models.put("agentId", JsonString(agentId))
    models.put("agentDir", JsonString(agentDir.toString()))
    models.put("path", JsonString(path.toString()))
    models.put("present", exists(path).toJsonValue())
    models.put("primaryModelRef", JsonString(gatewayAgentJsonString(state, "primaryModelRef", "")))
    models.put("runtimePrimaryModelRef", JsonString(gatewayAgentJsonString(state, "runtimePrimaryModelRef", "")))
    models.put("providerCount", gatewayAgentProviderCount(state).toJsonValue())
    models.put("credentialSource", gatewayAgentRedactObject(credentialSource))
    models.put("diagnostics", diagnostics)
    models.put("state", gatewayAgentRedactObject(state))
    let result = JsonObject()
    result.put("models", models)
    result
}

private func gatewayAgentModelsRefreshResultJson(refresh: CliModelRuntimeStateRefreshResult): JsonObject {
    let out = JsonObject()
    out.put("status", JsonString(refresh.status))
    out.put("reason", JsonString(refresh.reason))
    out.put("path", JsonString(refresh.path))
    out.put("refreshed", refresh.refreshed.toJsonValue())
    out
}

private func gatewayAgentModelsGetJson(request: GatewayRpcRequest): GatewayRpcResponse {
    let (agentId, scope) = gatewayAgentScopeForManagementRequest(request)
    if (!gatewayAgentJsonBool(gatewayAgentGetJson(agentId), "configured", false)) {
        return GatewayRpcResponse(false, request.method, error: "Agent \"${agentId}\" not found.")
    }
    let agentDir = Path(gatewayAgentJsonString(scope, "agentDir", gatewayAgentDefaultAgentDir(agentId).toString()))
    let path = CliModelRuntimeStateManager.ensureAgentRuntimeStateForScope(agentDir, scope)
    let diagnostics = JsonArray([])
    let state = gatewayAgentModelsReadState(path, diagnostics)
    GatewayRpcResponse(true, request.method, result: gatewayAgentModelsResponse(agentId, agentDir, path, state, diagnostics,
        gatewayAgentJsonObject(scope, "credentialSource")))
}

private func gatewayAgentModelsStateFromRequest(request: GatewayRpcRequest): (Bool, String, JsonObject) {
    match (request.params.get("state")) {
        case Some(v) =>
            try {
                return (true, "", gatewayAgentCloneObject(v.asObject()))
            } catch (_e: Exception) {
                return (false, "state must be a JSON object.", JsonObject())
            }
        case None => ()
    }
    match (request.params.get("content")) {
        case Some(v) =>
            let content = try { v.asString().getValue() } catch (_e: Exception) { v.toJsonString() }
            try {
                return (true, "", JsonValue.fromStr(content).asObject())
            } catch (_e: Exception) {
                return (false, "content must be valid JSON object.", JsonObject())
            }
        case None => (false, "Provide state object or content JSON.", JsonObject())
    }
}

private func gatewayAgentModelsSetJson(request: GatewayRpcRequest): GatewayRpcResponse {
    let (ok, error, state) = gatewayAgentModelsStateFromRequest(request)
    if (!ok) {
        return GatewayRpcResponse(false, request.method, error: error)
    }
    let (agentId, scope) = gatewayAgentScopeForManagementRequest(request)
    if (!gatewayAgentJsonBool(gatewayAgentGetJson(agentId), "configured", false)) {
        return GatewayRpcResponse(false, request.method, error: "Agent \"${agentId}\" not found.")
    }
    let agentDir = Path(gatewayAgentJsonString(scope, "agentDir", gatewayAgentDefaultAgentDir(agentId).toString()))
    if (!exists(agentDir)) {
        Directory.create(agentDir, recursive: true)
    }
    let path = CliModelRuntimeStateManager.agentRuntimePath(agentDir)
    File.writeTo(path, state.toJsonString().toArray())
    let diagnostics = JsonArray([])
    GatewayRpcResponse(true, request.method, result: gatewayAgentModelsResponse(agentId, agentDir, path, state, diagnostics,
        gatewayAgentJsonObject(scope, "credentialSource")))
}

private func gatewayAgentEntryAddAlias(entry: JsonObject, alias: String): Unit {
    let normalized = alias.trimAscii()
    if (normalized.isEmpty()) {
        return
    }
    let groupChat = match (entry.get("groupChat")) {
        case Some(v) =>
            try { gatewayAgentCloneObject(v.asObject()) } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let existing = gatewayAgentJsonArray(groupChat, "mentionPatterns")
    let next = JsonArray([])
    var saw = false
    for (i in 0..existing.size()) {
        let current = try { existing[i].asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        if (current.isEmpty()) {
            continue
        }
        if (current == normalized) {
            saw = true
        }
        next.add(JsonString(current))
    }
    if (!saw) {
        next.add(JsonString(normalized))
    }
    groupChat.put("mentionPatterns", next)
    entry.put("groupChat", groupChat)
}

private func gatewayAgentApplyAliasToAgent(root: JsonObject, agentId: String, alias: String): Unit {
    let normalized = gatewaySanitizeAgentId(agentId)
    if (normalized.isEmpty() || alias.trimAscii().isEmpty()) {
        return
    }
    let entries = gatewayAgentConfigEntries(root)
    let index = gatewayAgentConfigFindEntryIndex(entries, normalized)
    if (index < 0) {
        return
    }
    let nextEntries = JsonArray([])
    for (i in 0..entries.size()) {
        if (i == index) {
            let entry = try { gatewayAgentCloneObject(entries[i].asObject()) } catch (_e: Exception) { JsonObject() }
            gatewayAgentEntryAddAlias(entry, alias)
            nextEntries.add(entry)
        } else {
            nextEntries.add(entries[i])
        }
    }
    gatewayAgentConfigWriteEntries(root, nextEntries)
}

private func gatewayAgentApplyTeamAliases(root: JsonObject, aliases: JsonArray): Unit {
    for (i in 0..aliases.size()) {
        let aliasObj = try { aliases[i].asObject() } catch (_e: Exception) { JsonObject() }
        let alias = gatewayAgentJsonString(aliasObj, "alias", "").trimAscii()
        let agentId = gatewaySanitizeAgentId(gatewayAgentJsonString(aliasObj, "agentId", ""))
        gatewayAgentApplyAliasToAgent(root, agentId, alias)
    }
}

private func gatewayAgentTeamFindIndex(teams: JsonArray, teamId: String): Int64 {
    let normalized = gatewaySanitizeAgentId(teamId)
    for (i in 0..teams.size()) {
        let team = try { teams[i].asObject() } catch (_e: Exception) { JsonObject() }
        if (gatewaySanitizeAgentId(gatewayAgentJsonString(team, "id", "")) == normalized) {
            return i
        }
    }
    -1
}

private func gatewayAgentTeamMember(agentId: String, role: String, name: String): JsonObject {
    let row = JsonObject()
    row.put("agentId", JsonString(gatewaySanitizeAgentId(agentId)))
    row.put("role", JsonString(role))
    row.put("name", JsonString(name))
    row
}

private func gatewayAgentTeamTemplateMembers(teamId: String, template: String): JsonArray {
    let members = JsonArray([])
    if (template.trimAscii().toAsciiLower() == "pm-writer-reviewer") {
        members.add(gatewayAgentTeamMember("${teamId}-pm", "pm", "${teamId} PM"))
        members.add(gatewayAgentTeamMember("${teamId}-writer", "writer", "${teamId} Writer"))
        members.add(gatewayAgentTeamMember("${teamId}-reviewer", "reviewer", "${teamId} Reviewer"))
    }
    members
}

private func gatewayAgentEnsureManagedConfigEntry(root: JsonObject, agentId: String, name: String): JsonObject {
    let normalized = gatewaySanitizeAgentId(agentId)
    let entries = gatewayAgentConfigEntries(root)
    let index = gatewayAgentConfigFindEntryIndex(entries, normalized)
    let workspace = gatewayAgentDefaultWorkspaceDir(normalized).toString()
    let agentDir = gatewayAgentDefaultAgentDir(normalized).toString()
    let sessionsDir = gatewayAgentDefaultSessionsDir(normalized).toString()
    if (!exists(Path(agentDir))) {
        Directory.create(Path(agentDir), recursive: true)
    }
    if (!exists(Path(sessionsDir))) {
        Directory.create(Path(sessionsDir), recursive: true)
    }
    ensureMetisAgentWorkspace(Path(workspace))
    let manifestPath = Path(agentDir).join("AGENT.md")
    if (!exists(manifestPath)) {
        File.writeTo(manifestPath, gatewayAgentBuildDefaultManifest(normalized, name, workspace).toArray())
    }
    if (index >= 0) {
        return try { entries[index].asObject() } catch (_e: Exception) { JsonObject() }
    }
    let entry = JsonObject()
    entry.put("id", JsonString(normalized))
    entry.put("name", JsonString(if (name.trimAscii().isEmpty()) { normalized } else { name.trimAscii() }))
    entry.put("workspace", JsonString(workspace))
    entry.put("agentDir", JsonString(agentDir))
    entry.put("sessionsDir", JsonString(sessionsDir))
    let next = JsonArray([])
    for (i in 0..entries.size()) {
        next.add(entries[i])
    }
    next.add(entry)
    gatewayAgentConfigWriteEntries(root, next)
    entry
}

private func gatewayAgentPlanManagedConfigEntry(root: JsonObject, agentId: String, name: String): JsonObject {
    let normalized = gatewaySanitizeAgentId(agentId)
    let entries = gatewayAgentConfigEntries(root)
    let index = gatewayAgentConfigFindEntryIndex(entries, normalized)
    if (index >= 0) {
        return try { entries[index].asObject() } catch (_e: Exception) { JsonObject() }
    }
    let workspace = gatewayAgentDefaultWorkspaceDir(normalized).toString()
    let agentDir = gatewayAgentDefaultAgentDir(normalized).toString()
    let sessionsDir = gatewayAgentDefaultSessionsDir(normalized).toString()
    let entry = JsonObject()
    entry.put("id", JsonString(normalized))
    entry.put("name", JsonString(if (name.trimAscii().isEmpty()) { normalized } else { name.trimAscii() }))
    entry.put("workspace", JsonString(workspace))
    entry.put("agentDir", JsonString(agentDir))
    entry.put("sessionsDir", JsonString(sessionsDir))
    let next = JsonArray([])
    for (i in 0..entries.size()) {
        next.add(entries[i])
    }
    next.add(entry)
    gatewayAgentConfigWriteEntries(root, next)
    entry
}

private func gatewayAgentTeamMembersFromRequest(request: GatewayRpcRequest, teamId: String): JsonArray {
    match (request.params.get("members")) {
        case Some(v) =>
            try { return gatewayAgentCloneArray(v.asArray()) } catch (_e: Exception) { return JsonArray([]) }
        case None => ()
    }
    gatewayAgentTeamTemplateMembers(teamId, gatewayAgentRpcStringParam(request, ["template"], ""))
}

private func gatewayAgentTeamAliasesFromRequest(request: GatewayRpcRequest): JsonArray {
    match (request.params.get("aliases")) {
        case Some(v) =>
            try { gatewayAgentCloneArray(v.asArray()) } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func gatewayAgentTeamBroadcastFromRequest(request: GatewayRpcRequest): JsonObject {
    match (request.params.get("broadcast")) {
        case Some(v) =>
            try { return gatewayAgentCloneObject(v.asObject()) } catch (_e: Exception) { () }
        case None => ()
    }
    let broadcast = JsonObject()
    broadcast.put("enabled", false.toJsonValue())
    broadcast
}

private func gatewayAgentEnsureTeamMemberAgents(root: JsonObject, members: JsonArray): JsonArray {
    let createdOrPresent = JsonArray([])
    for (i in 0..members.size()) {
        let member = try { members[i].asObject() } catch (_e: Exception) { JsonObject() }
        let agentId = gatewaySanitizeAgentId(gatewayAgentJsonString(member, "agentId", ""))
        if (agentId.isEmpty()) {
            continue
        }
        let name = gatewayAgentJsonString(member, "name", agentId)
        let entry = gatewayAgentEnsureManagedConfigEntry(root, agentId, name)
        createdOrPresent.add(gatewayAgentSummaryRow(agentId, "custom", entry: entry, root: root))
    }
    createdOrPresent
}

private func gatewayAgentPlanTeamMemberAgents(root: JsonObject, members: JsonArray): Unit {
    for (i in 0..members.size()) {
        let member = try { members[i].asObject() } catch (_e: Exception) { JsonObject() }
        let agentId = gatewaySanitizeAgentId(gatewayAgentJsonString(member, "agentId", ""))
        if (agentId.isEmpty()) {
            continue
        }
        let name = gatewayAgentJsonString(member, "name", agentId)
        gatewayAgentPlanManagedConfigEntry(root, agentId, name)
    }
}

private func gatewayAgentTeamMemberIds(members: JsonArray): ArrayList<String> {
    let out = ArrayList<String>()
    for (i in 0..members.size()) {
        let member = try { members[i].asObject() } catch (_e: Exception) { JsonObject() }
        let agentId = gatewaySanitizeAgentId(gatewayAgentJsonString(member, "agentId", ""))
        if (!agentId.isEmpty() && !out.contains(agentId)) {
            out.add(agentId)
        }
    }
    out
}

private func gatewayAgentTeamNormalizeBindings(bindings: JsonArray, defaultAgentId: String): (JsonArray, JsonArray) {
    let out = JsonArray([])
    let errors = JsonArray([])
    for (i in 0..bindings.size()) {
        gatewayAgentAppendRouteBindingValue(out, errors, defaultAgentId, bindings[i], requireDefaultAgent: false)
    }
    (out, errors)
}

private func gatewayAgentValidateTeamBindingAgents(bindings: JsonArray, memberIds: ArrayList<String>): JsonArray {
    let errors = JsonArray([])
    for (i in 0..bindings.size()) {
        let binding = try { bindings[i].asObject() } catch (_e: Exception) { JsonObject() }
        let agentId = gatewaySanitizeAgentId(gatewayAgentJsonString(binding, "agentId", ""))
        if (!memberIds.contains(agentId)) {
            errors.add(JsonString("Team binding agent \"${agentId}\" is not a member of the team."))
        }
    }
    errors
}

private func gatewayAgentTeamApplyBindings(
    root: JsonObject,
    bindings: JsonArray,
    members: JsonArray,
    defaultAgentId: String
): (GatewayAgentBindingApplyResult, JsonArray) {
    let (routeBindings, parseErrors) = gatewayAgentTeamNormalizeBindings(bindings, defaultAgentId)
    if (parseErrors.size() > 0) {
        return (GatewayAgentBindingApplyResult(root, [], [], [], []), parseErrors)
    }
    let memberErrors = gatewayAgentValidateTeamBindingAgents(routeBindings, gatewayAgentTeamMemberIds(members))
    if (memberErrors.size() > 0) {
        return (GatewayAgentBindingApplyResult(root, [], [], [], []), memberErrors)
    }
    (gatewayApplyAgentRouteBindings(root, routeBindings), JsonArray([]))
}

private func gatewayAgentBindingConflictError(conflicts: Array<GatewayAgentBindingConflict>): String {
    if (conflicts.size == 0) {
        return ""
    }
    let first = conflicts[0]
    "Binding conflict for ${gatewayAgentBindingDescribe(first.binding)}; existing agent is \"${first.existingAgentId}\"."
}

private func gatewayAgentTeamsListJson(_request: GatewayRpcRequest): GatewayRpcResponse {
    let result = JsonObject()
    let teams = gatewayAgentTeamsList(gatewayAgentConfigRootCloneReadOnly())
    result.put("teams", teams)
    result.put("count", teams.size().toJsonValue())
    GatewayRpcResponse(true, "agents.teams.list", result: result)
}

private func gatewayAgentTeamGetJson(request: GatewayRpcRequest): GatewayRpcResponse {
    let root = gatewayAgentConfigRootCloneReadOnly()
    let teamId = gatewaySanitizeAgentId(gatewayAgentRpcStringParam(request, ["id", "teamId"], ""))
    let teams = gatewayAgentTeamsList(root)
    let index = gatewayAgentTeamFindIndex(teams, teamId)
    if (index < 0) {
        return GatewayRpcResponse(false, request.method, error: "Agent team \"${teamId}\" not found.")
    }
    let result = JsonObject()
    result.put("team", teams[index])
    GatewayRpcResponse(true, request.method, result: result)
}

private func gatewayAgentTeamCreateJson(request: GatewayRpcRequest): GatewayRpcResponse {
    let root = gatewayAgentConfigRootClone()
    let teamId = gatewaySanitizeAgentId(gatewayAgentRpcStringParam(request, ["id", "teamId"], ""))
    if (teamId.isEmpty()) {
        return GatewayRpcResponse(false, request.method, error: "Agent team id is required.")
    }
    let teams = gatewayAgentTeamsList(root)
    if (gatewayAgentTeamFindIndex(teams, teamId) >= 0) {
        return GatewayRpcResponse(false, request.method, error: "Agent team \"${teamId}\" already exists.")
    }
    let members = gatewayAgentTeamMembersFromRequest(request, teamId)
    if (members.size() == 0) {
        return GatewayRpcResponse(false, request.method, error: "Agent team requires members or a supported template.")
    }
    let team = JsonObject()
    team.put("id", JsonString(teamId))
    team.put("displayName", JsonString(gatewayAgentRpcStringParam(request, ["displayName", "name"], teamId)))
    let rawDefaultAgentId = gatewayAgentRpcStringParam(request, ["defaultAgentId"], "")
    let fallbackDefault = try { gatewayAgentJsonString(members[0].asObject(), "agentId", "") } catch (_e: Exception) { "" }
    let defaultAgentId = if (rawDefaultAgentId.isEmpty()) { gatewaySanitizeAgentId(fallbackDefault) } else { gatewaySanitizeAgentId(rawDefaultAgentId) }
    team.put("defaultAgentId", JsonString(defaultAgentId))
    team.put("members", members)
    let aliases = gatewayAgentTeamAliasesFromRequest(request)
    team.put("aliases", aliases)
    let rawBindings = match (request.params.get("bindings")) {
        case Some(v) =>
            try { gatewayAgentCloneArray(v.asArray()) } catch (_e: Exception) {
                return GatewayRpcResponse(false, request.method, error: "bindings must be an array.")
            }
        case None => JsonArray([])
    }
    team.put("bindings", rawBindings)
    let preflightRoot = gatewayAgentCloneObject(root)
    gatewayAgentPlanTeamMemberAgents(preflightRoot, members)
    var bindingApply = gatewayAgentEmptyBindingApplyJson(preflightRoot)
    if (rawBindings.size() > 0) {
        let (applyResult, bindingErrors) = gatewayAgentTeamApplyBindings(preflightRoot, rawBindings, members, defaultAgentId)
        if (bindingErrors.size() > 0) {
            return GatewayRpcResponse(false, request.method, error: bindingErrors.toJsonString())
        }
        if (applyResult.conflicts.size > 0) {
            return GatewayRpcResponse(false, request.method, error: gatewayAgentBindingConflictError(applyResult.conflicts), result: gatewayAgentBindingApplyJson(applyResult))
        }
        bindingApply = gatewayAgentBindingApplyJson(applyResult)
    }
    team.put("broadcast", gatewayAgentTeamBroadcastFromRequest(request))
    let memberAgents = gatewayAgentEnsureTeamMemberAgents(preflightRoot, members)
    let nextTeams = JsonArray([])
    for (i in 0..teams.size()) {
        nextTeams.add(teams[i])
    }
    nextTeams.add(team)
    gatewayAgentTeamsWriteList(preflightRoot, nextTeams)
    gatewayAgentApplyTeamAliases(preflightRoot, aliases)
    MetisConfigManager.writeRoot(preflightRoot)
    let result = JsonObject()
    result.put("team", team)
    result.put("agents", memberAgents)
    result.put("bindingApply", bindingApply)
    GatewayRpcResponse(true, request.method, result: result)
}

private func gatewayAgentTeamUpdateJson(request: GatewayRpcRequest): GatewayRpcResponse {
    let root = gatewayAgentConfigRootClone()
    let teamId = gatewaySanitizeAgentId(gatewayAgentRpcStringParam(request, ["id", "teamId"], ""))
    let teams = gatewayAgentTeamsList(root)
    let index = gatewayAgentTeamFindIndex(teams, teamId)
    if (index < 0) {
        return GatewayRpcResponse(false, request.method, error: "Agent team \"${teamId}\" not found.")
    }
    let team = try { gatewayAgentCloneObject(teams[index].asObject()) } catch (_e: Exception) { JsonObject() }
    let preflightRoot = gatewayAgentCloneObject(root)
    gatewayAgentPutRequestString(team, request, ["displayName", "name"], "displayName")
    gatewayAgentPutRequestString(team, request, ["defaultAgentId"], "defaultAgentId")
    var membersChanged = false
    match (request.params.get("members")) {
        case Some(v) =>
            try {
                let members = gatewayAgentCloneArray(v.asArray())
                team.put("members", members)
                gatewayAgentPlanTeamMemberAgents(preflightRoot, members)
                membersChanged = true
            } catch (_e: Exception) {
                return GatewayRpcResponse(false, request.method, error: "members must be an array.")
            }
        case None => ()
    }
    match (request.params.get("aliases")) {
        case Some(v) =>
            try {
                let aliases = gatewayAgentCloneArray(v.asArray())
                team.put("aliases", aliases)
            } catch (_e: Exception) {
                return GatewayRpcResponse(false, request.method, error: "aliases must be an array.")
            }
        case None => ()
    }
    let effectiveMembers = gatewayAgentJsonArray(team, "members")
    if (!membersChanged) {
        gatewayAgentPlanTeamMemberAgents(preflightRoot, effectiveMembers)
    }
    let rawDefaultAgentId = gatewaySanitizeAgentId(gatewayAgentJsonString(team, "defaultAgentId", ""))
    let fallbackDefault = try { gatewayAgentJsonString(effectiveMembers[0].asObject(), "agentId", "") } catch (_e: Exception) { "" }
    let defaultAgentId = if (rawDefaultAgentId.isEmpty()) { gatewaySanitizeAgentId(fallbackDefault) } else { rawDefaultAgentId }
    var bindingApply = gatewayAgentEmptyBindingApplyJson(preflightRoot)
    match (request.params.get("bindings")) {
        case Some(v) =>
            let rawBindings = try { gatewayAgentCloneArray(v.asArray()) } catch (_e: Exception) {
                return GatewayRpcResponse(false, request.method, error: "bindings must be an array.")
            }
            let (applyResult, bindingErrors) = gatewayAgentTeamApplyBindings(preflightRoot, rawBindings, effectiveMembers, defaultAgentId)
            if (bindingErrors.size() > 0) {
                return GatewayRpcResponse(false, request.method, error: bindingErrors.toJsonString())
            }
            if (applyResult.conflicts.size > 0) {
                return GatewayRpcResponse(false, request.method, error: gatewayAgentBindingConflictError(applyResult.conflicts), result: gatewayAgentBindingApplyJson(applyResult))
            }
            team.put("bindings", rawBindings)
            bindingApply = gatewayAgentBindingApplyJson(applyResult)
        case None => ()
    }
    match (request.params.get("broadcast")) {
        case Some(v) =>
            try { team.put("broadcast", gatewayAgentCloneObject(v.asObject())) } catch (_e: Exception) {
                return GatewayRpcResponse(false, request.method, error: "broadcast must be an object.")
            }
        case None => ()
    }
    let nextTeams = JsonArray([])
    for (i in 0..teams.size()) {
        if (i == index) {
            nextTeams.add(team)
        } else {
            nextTeams.add(teams[i])
        }
    }
    gatewayAgentTeamsWriteList(preflightRoot, nextTeams)
    let finalAliases = gatewayAgentJsonArray(team, "aliases")
    gatewayAgentApplyTeamAliases(preflightRoot, finalAliases)
    let memberAgents = gatewayAgentEnsureTeamMemberAgents(preflightRoot, effectiveMembers)
    MetisConfigManager.writeRoot(preflightRoot)
    let result = JsonObject()
    result.put("team", team)
    result.put("agents", memberAgents)
    result.put("bindingApply", bindingApply)
    GatewayRpcResponse(true, request.method, result: result)
}

private func gatewayAgentTeamDeleteJson(request: GatewayRpcRequest): GatewayRpcResponse {
    let root = gatewayAgentConfigRootClone()
    let teamId = gatewaySanitizeAgentId(gatewayAgentRpcStringParam(request, ["id", "teamId"], ""))
    let teams = gatewayAgentTeamsList(root)
    let index = gatewayAgentTeamFindIndex(teams, teamId)
    if (index < 0) {
        return GatewayRpcResponse(false, request.method, error: "Agent team \"${teamId}\" not found.")
    }
    let nextTeams = JsonArray([])
    var removed = JsonObject()
    for (i in 0..teams.size()) {
        if (i == index) {
            removed = try { teams[i].asObject() } catch (_e: Exception) { JsonObject() }
        } else {
            nextTeams.add(teams[i])
        }
    }
    gatewayAgentTeamsWriteList(root, nextTeams)
    MetisConfigManager.writeRoot(root)
    let result = JsonObject()
    result.put("team", removed)
    result.put("removed", true.toJsonValue())
    GatewayRpcResponse(true, request.method, result: result)
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
    let existingEntry = try { entries[index].asObject() } catch (_e: Exception) { JsonObject() }
    let avatar = gatewayAgentRpcStringParam(request, ["avatar"], "").trimAscii()
    if (!avatar.isEmpty()) {
        let workspace = gatewayAgentJsonString(existingEntry, "workspace", gatewayAgentDefaultWorkspaceDir(agentId).toString())
        let validation = validateMetisIdentityAvatar(Path(workspace), avatar)
        if (!validation.ok) {
            return GatewayRpcResponse(false, "agents.set-identity", error: "Invalid avatar: ${validation.reason}")
        }
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

private func gatewayAppendCustomAgentJsonRow(out: JsonArray, seen: ArrayList<String>, agentId: String, path: Path): Unit {
    let normalized = gatewaySanitizeAgentId(agentId)
    if (normalized.isEmpty() || gatewayAgentArrayContains(seen, normalized)) {
        return
    }
    let row = JsonObject()
    row.put("id", JsonString(normalized))
    row.put("kind", JsonString("custom"))
    row.put("path", JsonString(path.toString()))
    row.put("available", true.toJsonValue())
    row.put("configured", true.toJsonValue())
    row.put("health", JsonString("ok"))
    row.put("memory", gatewayAgentMemoryJson(normalized))
    out.add(row)
    seen.add(normalized)
}

private func gatewayCustomAgentsJson(): JsonArray {
    let root = gatewayAgentConfigRootClone()
    let out = JsonArray([])
    let seen = ArrayList<String>()
    let entries = gatewayAgentConfigEntries(root)
    for (i in 0..entries.size()) {
        let cfg = try { entries[i].asObject() } catch (_e: Exception) { JsonObject() }
        let agentId = gatewayAgentJsonString(cfg, "id", "")
        let agentDir = gatewayAgentJsonString(cfg, "agentDir", "")
        if (!agentId.trimAscii().isEmpty() && !agentDir.trimAscii().isEmpty() && exists(Path(agentDir).join("AGENT.md"))) {
            gatewayAppendCustomAgentJsonRow(out, seen, agentId, Path(agentDir))
        }
    }
    for (agentDir in CliConfig.subagentDirs) {
        if (!exists(agentDir)) {
            continue
        }
        if (exists(agentDir.join("AGENT.md"))) {
            gatewayAppendCustomAgentJsonRow(out, seen, agentDir.fileName, agentDir)
            continue
        }
        let managedAgentDir = agentDir.join("agent")
        if (exists(managedAgentDir.join("AGENT.md"))) {
            gatewayAppendCustomAgentJsonRow(out, seen, agentDir.fileName, managedAgentDir)
            continue
        }
        for (entry in Directory.readFrom(agentDir)) {
            if (!entry.isDirectory()) {
                continue
            }
            if (entry.name == "agent") {
                continue
            }
            let manifest = agentDir.join(entry.name).join("AGENT.md")
            if (!exists(manifest)) {
                continue
            }
            gatewayAppendCustomAgentJsonRow(out, seen, entry.name, agentDir.join(entry.name))
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

private func gatewayAgentPutResolvedScopePaths(row: JsonObject, scope: JsonObject): Unit {
    for ((targetKey, scopeKey) in [
        ("workspace", "workspaceDir"),
        ("workspaceDir", "workspaceDir"),
        ("agentDir", "agentDir"),
        ("sessionsDir", "sessionsDir"),
        ("modelsJsonPath", "modelsJsonPath"),
        ("authProfilesPath", "authProfilesPath")
    ]) {
        if (row.get(targetKey).isSome()) {
            continue
        }
        let value = gatewayAgentJsonString(scope, scopeKey, "").trimAscii()
        if (!value.isEmpty()) {
            row.put(targetKey, JsonString(value))
        }
    }
}

private func gatewayAgentGetJson(agentId: String): JsonObject {
    let normalized = agentId.trimAscii().toAsciiLower()
    let root = gatewayAgentConfigRootCloneReadOnly()
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
            let teamIds = gatewayAgentTeamIdsForAgent(root, id)
            if (teamIds.size() > 0) {
                row.put("teamIds", teamIds)
            }
            row.put("skills", gatewayAgentSkillsJson(id))
            row.put("tools", gatewayAgentToolsJson(id, gatewayDefaultChatToolNames()))
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
            let configuredEntry = gatewayAgentConfigEntry(root, id)
            let row = gatewayAgentSummaryRow(id, "custom", entry: configuredEntry, root: root)
            row.put("path", obj.get("path") ?? JsonString(""))
            row.put("configured", true.toJsonValue())
            gatewayAgentPutResolvedScopePaths(
                row,
                MetisAgentScope.resolve(root, agentId: id, homeRoot: MetisPaths.homeRootReadOnly(), defaultWorkspace: MetisPaths.workspaceRootReadOnly())
            )
            row.put("memory", gatewayAgentMemoryJson(id))
            return row
        }
    }
    let row = JsonObject()
    row.put("id", JsonString(normalized))
    row.put("configured", false.toJsonValue())
    row.put("tools", gatewayAgentToolsJson(normalized, gatewayDefaultChatToolNames()))
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
    if (method == "agents.migration.dryRun" || method == "agents.migration.dry-run") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let root = gatewayAgentScopeRootFromRequest(requestValue)
        let proposedBindings = gatewayAgentJsonArray(requestValue.params, "proposedBindings")
        let homeRoot = gatewayAgentScopePathParam(requestValue, "homeRoot", MetisPaths.homeRootReadOnly())
        let defaultWorkspace = gatewayAgentScopePathParam(requestValue, "defaultWorkspace", MetisPaths.workspaceRootReadOnly())
        let result = gatewayAgentTeamMigrationDryRun(root, proposedBindings: proposedBindings,
            homeRoot: homeRoot, defaultWorkspace: defaultWorkspace)
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "agents.add") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let response = gatewayAgentAddJson(requestValue)
        return Some(GatewayRpcResponse(response.ok, method, result: response.result, error: response.error))
    }
    if (method == "agents.update") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let response = gatewayAgentUpdateJson(requestValue)
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
    if (method == "agents.files.list") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let response = gatewayAgentWorkspaceFilesListJson(requestValue)
        return Some(GatewayRpcResponse(response.ok, method, result: response.result, error: response.error))
    }
    if (method == "agents.files.get") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let response = gatewayAgentWorkspaceFileJson(requestValue)
        return Some(GatewayRpcResponse(response.ok, method, result: response.result, error: response.error))
    }
    if (method == "agents.files.set") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let content = gatewayAgentRpcRawStringParam(requestValue, ["content"], "")
        let response = gatewayAgentWorkspaceFileJson(requestValue, content: content, includeContent: true)
        return Some(GatewayRpcResponse(response.ok, method, result: response.result, error: response.error))
    }
    if (method == "agents.models.status" || method == "agents.models.get") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let response = gatewayAgentModelsGetJson(requestValue)
        return Some(GatewayRpcResponse(response.ok, method, result: response.result, error: response.error))
    }
    if (method == "agents.models.set") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let response = gatewayAgentModelsSetJson(requestValue)
        return Some(GatewayRpcResponse(response.ok, method, result: response.result, error: response.error))
    }
    if (method == "agents.teams.list") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let response = gatewayAgentTeamsListJson(requestValue)
        return Some(GatewayRpcResponse(response.ok, method, result: response.result, error: response.error))
    }
    if (method == "agents.teams.get") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let response = gatewayAgentTeamGetJson(requestValue)
        return Some(GatewayRpcResponse(response.ok, method, result: response.result, error: response.error))
    }
    if (method == "agents.teams.create") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let response = gatewayAgentTeamCreateJson(requestValue)
        return Some(GatewayRpcResponse(response.ok, method, result: response.result, error: response.error))
    }
    if (method == "agents.teams.update") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let response = gatewayAgentTeamUpdateJson(requestValue)
        return Some(GatewayRpcResponse(response.ok, method, result: response.result, error: response.error))
    }
    if (method == "agents.teams.delete") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let response = gatewayAgentTeamDeleteJson(requestValue)
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
