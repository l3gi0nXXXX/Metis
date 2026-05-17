package metis.gateway.runtime

import magic.jsonable.*

import metis.core.gatewaySubagentResolveAgent
import metis.core.config.{CliConfig, CliModelRuntimeStateManager, CliSettingManager, MetisConfigManager, MetisProcessEnvironmentLock}
import metis.gateway.core.{GatewayAgentRouteInput, GatewayResolvedSessionTurnResult, GatewaySessionExecutionResult, gatewayAgentTeamBroadcastAggregateJson, gatewayResolveAgentRoute, gatewayResolveAgentTeamBroadcastPlan, gatewayResolveSessionContextWithAgentRoute}
import metis.gateway.session.{GatewayIngressSource, GatewaySessionRequest}

import std.collection.ArrayList
import std.env.{getVariable, setVariable}
import std.fs.{Directory, File, Path, exists, remove}
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString}

private func agentsTestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func agentsTestStringArray(values: Array<String>): JsonArray {
    let out = JsonArray([])
    for (value in values) {
        out.add(JsonString(value))
    }
    out
}

private func agentsTestObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func agentsTestArray(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asArray() } catch (_: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func agentsTestBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_: Exception) { false }
        case None => false
    }
}

private func agentsTestArrayContains(arr: JsonArray, expected: String): Bool {
    for (i in 0..arr.size()) {
        try {
            if (arr[i].asString().getValue() == expected) {
                return true
            }
        } catch (_: Exception) {
            ()
        }
    }
    false
}

private func agentsTestObjectArrayContainsString(obj: JsonObject, key: String, expected: String): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try { agentsTestArrayContains(v.asArray(), expected) } catch (_: Exception) { false }
        case None => false
    }
}

private func agentsTestFindObjectById(rows: JsonArray, id: String): JsonObject {
    for (i in 0..rows.size()) {
        let row = try { rows[i].asObject() } catch (_: Exception) { JsonObject() }
        if (agentsTestString(row, "id") == id || agentsTestString(row, "agentId") == id || agentsTestString(row, "name") == id) {
            return row
        }
    }
    JsonObject()
}

private func agentsTestConfiguredAgent(root: JsonObject, id: String): JsonObject {
    let agents = agentsTestObject(root, "agents")
    let list = match (agents.get("list")) {
        case Some(v) => try { v.asArray() } catch (_: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    agentsTestFindObjectById(list, id)
}

private func agentsTestGatewayAccount(root: JsonObject, channel: String, accountId: String): JsonObject {
    let gateway = agentsTestObject(root, "gateway")
    let channelConfig = agentsTestObject(gateway, channel)
    let accounts = agentsTestObject(channelConfig, "accounts")
    agentsTestObject(accounts, accountId)
}

private func agentsTestFindChannelAccountSummary(rows: JsonArray, channel: String, accountId: String): JsonObject {
    for (i in 0..rows.size()) {
        let row = try { rows[i].asObject() } catch (_: Exception) { JsonObject() }
        if (agentsTestString(row, "channel") == channel && agentsTestString(row, "accountId") == accountId) {
            return row
        }
    }
    JsonObject()
}

private func agentsTestTeamMember(agentId: String, role!: String = "", name!: String = ""): JsonObject {
    let member = JsonObject()
    member.put("agentId", JsonString(agentId))
    if (!role.trimAscii().isEmpty()) {
        member.put("role", JsonString(role))
    }
    if (!name.trimAscii().isEmpty()) {
        member.put("name", JsonString(name))
    }
    member
}

private func agentsTestTeamAlias(alias: String, agentId: String): JsonObject {
    let row = JsonObject()
    row.put("alias", JsonString(alias))
    row.put("agentId", JsonString(agentId))
    row
}

private func agentsTestRouteBinding(
    agentId: String,
    channel: String,
    accountId!: String = "",
    peerKind!: String = "",
    peerId!: String = "",
    guildId!: String = "",
    teamId!: String = "",
    roles!: Array<String> = []
): JsonObject {
    let binding = JsonObject()
    binding.put("type", JsonString("route"))
    binding.put("agentId", JsonString(agentId))
    let matchObj = JsonObject()
    matchObj.put("channel", JsonString(channel))
    if (!accountId.trimAscii().isEmpty()) {
        matchObj.put("accountId", JsonString(accountId))
    }
    if (!peerKind.trimAscii().isEmpty() || !peerId.trimAscii().isEmpty()) {
        let peer = JsonObject()
        peer.put("kind", JsonString(peerKind))
        peer.put("id", JsonString(peerId))
        matchObj.put("peer", peer)
    }
    if (!guildId.trimAscii().isEmpty()) {
        matchObj.put("guildId", JsonString(guildId))
    }
    if (!teamId.trimAscii().isEmpty()) {
        matchObj.put("teamId", JsonString(teamId))
    }
    if (roles.size > 0) {
        matchObj.put("roles", agentsTestStringArray(roles))
    }
    binding.put("match", matchObj)
    binding
}

private func agentsTestAddAgent(agentId: String): GatewayRpcResponse {
    let params = JsonObject()
    params.put("id", JsonString(agentId))
    handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: params))).getOrThrow()
}

private func agentsTestRawBindings(): JsonArray {
    MetisConfigManager.rawConfig().getOrThrow().get("bindings").getOrThrow().asArray()
}

private func agentsTestClean(path: Path): Unit {
    try {
        if (exists(path)) {
            remove(path, recursive: true)
        }
    } catch (_: Exception) {
        ()
    }
}

private func withAgentsTempHome<T>(label: String, block: (Path) -> T): T {
    synchronized(MetisProcessEnvironmentLock) {
        let home = Path("/tmp/${label}")
        try {
            remove(home, recursive: true)
        } catch (_: Exception) {
            ()
        }
        Directory.create(home, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", home.toString())
        CliConfig.invalidatePathCache()
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
        try {
            return block(home)
        } finally {
            match (oldHome) {
                case Some(value) => setVariable("METIS_HOME", value)
                case None => setVariable("METIS_HOME", "")
            }
            CliConfig.invalidatePathCache()
            MetisConfigManager.invalidate()
            CliSettingManager.invalidate()
            try {
                remove(home, recursive: true)
            } catch (_: Exception) {
                ()
            }
        }
    }
}

@Test
public class GatewayServerMethodsAgentsTest {
    @TestCase
    public func agentRoutingUsesUnifiedSessionContext(): Unit {
        let params = JsonObject()
        params.put("agentId", JsonString("general"))
        params.put("channel", JsonString("cli"))
        params.put("source", JsonString("cli"))
        params.put("session", JsonString("main"))
        params.put("text", JsonString("hello"))
        let response = handleGatewayAgentsFamily("agent.routing", request: Some(GatewayRpcRequest("agent.routing", params: params))).getOrThrow()
        @Expect(response.ok, true)
        let result = response.result.asObject()
        let routing = result.get("routing").getOrThrow().asObject()
        @Expect(agentsTestString(routing, "sessionKey"), "agent:main:main")
        let deliveryTarget = routing.get("deliveryTarget").getOrThrow().asObject()
        @Expect(agentsTestString(deliveryTarget, "replyChannel"), "cli")
        let actions = routing.get("actions").getOrThrow().asArray()
        let invoke = actions[0].asObject().get("params").getOrThrow().asObject()
        @Expect(agentsTestString(invoke, "session"), "agent:main:main")
        @Expect(agentsTestString(invoke, "channel"), "cli")
    }

    @TestCase
    public func agentRoutingPreservesChannelStyleSessionHints(): Unit {
        let params = JsonObject()
        params.put("agentId", JsonString("general"))
        params.put("channel", JsonString("qq"))
        params.put("session", JsonString("qq:direct:user:42"))
        let response = handleGatewayAgentsFamily("agent.routing", request: Some(GatewayRpcRequest("agent.routing", params: params))).getOrThrow()
        @Expect(response.ok, true)
        let result = response.result.asObject()
        let routing = result.get("routing").getOrThrow().asObject()
        @Expect(agentsTestString(routing, "sessionKey"), "qq:direct:user:42")
        let deliveryTarget = routing.get("deliveryTarget").getOrThrow().asObject()
        @Expect(agentsTestString(deliveryTarget, "replyChannel"), "qq")
        let actions = routing.get("actions").getOrThrow().asArray()
        let invoke = actions[0].asObject().get("params").getOrThrow().asObject()
        @Expect(agentsTestString(invoke, "session"), "qq:direct:user:42")
    }

    @TestCase
    public func resolvedInvokeParamsUseUnifiedSessionKey(): Unit {
        let params = JsonObject()
        params.put("agentId", JsonString("general"))
        params.put("channel", JsonString("cli"))
        params.put("source", JsonString("cli"))
        params.put("session", JsonString("main"))
        params.put("lane", JsonString("primary"))

        let invoke = gatewayAgentResolvedInvokeParams("main", GatewayRpcRequest("agent.invoke", params: params))
        @Expect(agentsTestString(invoke, "session"), "agent:main:main:lane:primary")
        @Expect(agentsTestString(invoke, "channel"), "cli")
        @Expect(agentsTestString(invoke, "source"), "cli")
    }

    @TestCase
    public func agentInspectIncludesMemoryRuntimeSummary(): Unit {
        let params = JsonObject()
        params.put("agentId", JsonString("general"))
        let response = handleGatewayAgentsFamily("agent.get", request: Some(GatewayRpcRequest("agent.get", params: params))).getOrThrow()
        @Expect(response.ok, true)
        let result = response.result.asObject()
        let agent = result.get("agent").getOrThrow().asObject()
        @Expect(agent.get("memory").isSome(), true)
        @Expect(agent.get("tools").isSome(), true)
        let tools = agent.get("tools").getOrThrow().asObject()
        @Expect(tools.get("policySource").isSome(), true)
        @Expect(tools.get("visibleTools").isSome(), true)
        let memory = agent.get("memory").getOrThrow().asObject()
        @Expect(memory.get("resolvedBackendConfig").isSome(), true)
        @Expect(memory.get("backendSelection").isSome(), true)
        @Expect(memory.get("agentScopedResolve").isSome(), true)
        @Expect(memory.get("activeMemoryPlugin").isSome(), true)
        @Expect(memory.get("activeSearchBackend").isSome(), true)
        @Expect(memory.get("activeOrchestrationBackend").isSome(), true)
        let resolved = memory.get("resolvedBackendConfig").getOrThrow().asObject()
        @Expect(agentsTestString(resolved, "agentId"), "main")
        @Expect(agentsTestString(resolved, "purpose"), "agents-inspect")
    }

    @TestCase
    public func agentsSummaryExposesGatewayAgentContract(): Unit {
        let response = handleGatewayAgentsFamily("agents.summary").getOrThrow()
        @Expect(response.ok, true)
        let result = response.result.asObject()
        let agents = result.get("agents").getOrThrow().asObject()
        @Expect(agentsTestString(agents, "defaultId"), "main")
        @Expect(agentsTestString(agents, "mainKey"), "main")
        @Expect(agentsTestString(agents, "scope"), "global")
        let rows = agents.get("agents").getOrThrow().asArray()
        @Expect(rows.size() > 0, true)
        let first = rows[0].asObject()
        @Expect(agentsTestString(first, "id"), "main")
        @Expect(agentsTestString(first, "kind"), "builtin")
        @Expect(first.get("skills").isSome(), true)
    }

    @TestCase
    public func agentsStatusCarriesAggregatedAgentRows(): Unit {
        let response = handleGatewayAgentsFamily("agents.status").getOrThrow()
        @Expect(response.ok, true)
        let result = response.result.asObject()
        @Expect(agentsTestString(result, "defaultId"), "main")
        @Expect(agentsTestString(result, "mainKey"), "main")
        @Expect(agentsTestString(result, "scope"), "global")
        let rows = result.get("agents").getOrThrow().asArray()
        @Expect(rows.size() > 0, true)
        let first = rows[0].asObject()
        @Expect(agentsTestString(first, "id"), "main")
        @Expect(first.get("skills").isSome(), true)
    }

    @TestCase
    public func agentsScopeHelpersExposeReadOnlyResolvedAgentScope(): Unit {
        let home = Path("/tmp").join("metis-agent-scope-gateway-test")
        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        defaults.put("workspace", JsonString(home.join("team").toString()))
        defaults.put("skills", agentsTestStringArray(["safe-default"]))
        let tools = JsonObject()
        tools.put("allow", agentsTestStringArray(["fileRead"]))
        defaults.put("tools", tools)
        agents.put("defaults", defaults)
        let list = JsonArray([])
        let pm = JsonObject()
        pm.put("id", JsonString("pm"))
        pm.put("default", JsonBool(true))
        list.add(pm)
        let writer = JsonObject()
        writer.put("id", JsonString("writer"))
        writer.put("skills", agentsTestStringArray(["writer-skill"]))
        list.add(writer)
        agents.put("list", list)
        root.put("agents", agents)

        let summary = gatewayResolveAgentsScopeSummaryFromRoot(root, homeRoot: home, defaultWorkspace: home.join("workspaces"))
        @Expect(agentsTestString(summary, "defaultAgentId"), "pm")
        @Expect(summary.get("agents").getOrThrow().asArray().size(), 2)

        let scope = gatewayResolveAgentScopeFromRoot(root, agentId: "writer", homeRoot: home, defaultWorkspace: home.join("workspaces"))
        @Expect(agentsTestString(scope, "agentId"), "writer")
        @Expect(agentsTestString(scope, "workspaceDir"), home.join("team").join("writer").toString())
        @Expect(agentsTestString(scope, "agentDir"), home.join("agents").join("writer").join("agent").toString())
        @Expect(agentsTestString(scope, "modelsJsonPath"), home.join("agents").join("writer").join("agent").join("models.json").toString())
        @Expect(agentsTestString(scope, "authProfilesPath"), home.join("agents").join("writer").join("agent").join("auth-profiles.json").toString())
        @Expect(agentsTestString(scope, "sessionsDir"), home.join("agents").join("writer").join("sessions").toString())
        @Expect(scope.get("skillsPolicy").getOrThrow().asObject().toJsonString().contains("writer-skill"), true)
        @Expect(scope.get("toolsPolicy").getOrThrow().asObject().toJsonString().contains("fileRead"), true)

        let defaultScope = gatewayResolveDefaultAgentScopeFromRoot(root, homeRoot: home, defaultWorkspace: home.join("workspaces"))
        @Expect(agentsTestString(defaultScope, "agentId"), "pm")
    }

    @TestCase
    public func agentScopeRpcUsesInjectedTempRootWithoutCreatingConfig(): Unit {
        let home = Path("/tmp").join("metis-agent-scope-rpc-readonly")
        agentsTestClean(home)
        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        defaults.put("workspace", JsonString(home.join("team").toString()))
        defaults.put("model", JsonString("qwen:qwen-plus"))
        agents.put("defaults", defaults)
        let list = JsonArray([])
        let pm = JsonObject()
        pm.put("id", JsonString("pm"))
        pm.put("default", JsonBool(true))
        list.add(pm)
        agents.put("list", list)
        root.put("agents", agents)
        let models = JsonObject()
        let providers = JsonObject()
        let qwen = JsonObject()
        qwen.put("apiKey", JsonString("test-key"))
        providers.put("qwen", qwen)
        models.put("providers", providers)
        root.put("models", models)

        let params = JsonObject()
        params.put("agentId", JsonString("pm"))
        params.put("configRoot", root)
        params.put("homeRoot", JsonString(home.toString()))
        params.put("defaultWorkspace", JsonString(home.join("workspace").toString()))
        let response = handleGatewayAgentsFamily("agent.scope", request: Some(GatewayRpcRequest("agent.scope", params: params))).getOrThrow()
        @Expect(response.ok, true)
        @Expect(exists(home), false)
        let scope = response.result.asObject().get("scope").getOrThrow().asObject()
        @Expect(agentsTestString(scope, "agentId"), "pm")
        @Expect(agentsTestString(scope, "modelRef"), "qwen:qwen-plus")
        @Expect(agentsTestBool(agentsTestObject(scope, "accountSummary"), "apiKeyConfigured"), true)
    }

    @TestCase
    public func agentsScopeRpcReturnsMainDefaultAndGeneralAliasDiagnostic(): Unit {
        let home = Path("/tmp").join("metis-agent-scope-rpc-empty")
        agentsTestClean(home)
        let params = JsonObject()
        params.put("configRoot", JsonObject())
        params.put("homeRoot", JsonString(home.toString()))
        params.put("defaultWorkspace", JsonString(home.join("workspace").toString()))
        let response = handleGatewayAgentsFamily("agents.scope", request: Some(GatewayRpcRequest("agents.scope", params: params))).getOrThrow()
        @Expect(response.ok, true)
        @Expect(exists(home), false)
        let scope = response.result.asObject().get("scope").getOrThrow().asObject()
        @Expect(agentsTestString(scope, "defaultAgentId"), "main")
        let rows = scope.get("agents").getOrThrow().asArray()
        @Expect(rows.size(), 1)
        @Expect(agentsTestString(rows[0].asObject(), "agentId"), "main")
        @Expect(scope.get("diagnostics").getOrThrow().asArray().toJsonString().contains("general-alias"), true)
    }

    @TestCase
    public func agentsRuntimeProfileExposesUnifiedGatewayMainRuntimeCoverage(): Unit {
        let response = handleGatewayAgentsFamily("agents.runtime.profile").getOrThrow()
        @Expect(response.ok, true)
        let result = response.result.asObject()
        let runtime = result.get("runtime").getOrThrow().asObject()
        @Expect(agentsTestString(runtime, "kind"), "gateway-main-runtime-profile")
        @Expect(agentsTestString(runtime, "runtime"), "gateway-main")
        @Expect(runtime.get("requiredCoreTools").isSome(), true)
        @Expect(runtime.get("currentTools").isSome(), true)
        @Expect(runtime.get("effectiveTools").isSome(), true)
        @Expect(runtime.get("missingCoreTools").isSome(), true)
        @Expect(runtime.get("extendedSurfaceTools").isSome(), true)
        @Expect(runtime.get("missingExtendedSurfaceTools").isSome(), true)
        @Expect(runtime.get("authorizationProfile").isSome(), true)
        @Expect(runtime.get("ingresses").isSome(), true)
        @Expect(runtime.get("coversUnifiedCoreBaseline").getOrThrow().asBool().getValue(), true)
        let authorizationProfile = runtime.get("authorizationProfile").getOrThrow().asObject()
        @Expect(agentsTestString(authorizationProfile, "toolAvailability"), "registered-unified")
        @Expect(agentsTestString(authorizationProfile, "authorizationModel"), "policy-gated")
        @Expect(agentsTestString(authorizationProfile, "rejectionContract"), "deny-with-reason")
        @Expect(agentsTestString(authorizationProfile, "enforcementStage"), "runtime-tool-filter")
        @Expect(agentsTestString(authorizationProfile, "approvalSurface"), "native-or-manual")
        @Expect(authorizationProfile.get("controls").isSome(), true)
        @Expect(authorizationProfile.get("gatewayActionPolicy").isSome(), true)
        let gatewayActionPolicy = authorizationProfile.get("gatewayActionPolicy").getOrThrow().asObject()
        @Expect(agentsTestString(gatewayActionPolicy, "mode"), "owner-policy-approval-protected-path")
        @Expect(gatewayActionPolicy.get("readOnlyActions").getOrThrow().asArray().toJsonString().contains("\"status\""), true)
        @Expect(gatewayActionPolicy.get("ownerApprovedActions").getOrThrow().asArray().toJsonString().contains("\"restart\""), true)
        @Expect(gatewayActionPolicy.get("explicitRequestActions").getOrThrow().asArray().toJsonString().contains("\"config.apply\""), true)
        @Expect(gatewayActionPolicy.get("autoOwnerApprovedSources").getOrThrow().asArray().toJsonString().contains("\"cli\""), true)
        @Expect(gatewayActionPolicy.get("autoOwnerApprovedSources").getOrThrow().asArray().toJsonString().contains("\"control-ui\""), true)
        @Expect(gatewayActionPolicy.get("ownerAuthorizationSignals").getOrThrow().asArray().toJsonString().contains("\"operator-scopes\""), true)
        @Expect(gatewayActionPolicy.get("contextIdentityFields").getOrThrow().asArray().toJsonString().contains("\"declaredUser\""), true)
        @Expect(gatewayActionPolicy.get("contextIdentityFields").getOrThrow().asArray().toJsonString().contains("\"operatorScopes\""), true)
        @Expect(agentsTestString(gatewayActionPolicy, "ownerInferenceMode"), "runtime-ingress-derived")
        @Expect(agentsTestString(gatewayActionPolicy, "explicitRequestInference"), "runtime-context-prompt-derived")
        @Expect(gatewayActionPolicy.get("protectedConfigPaths").getOrThrow().asArray().toJsonString().contains("\"gateway.auth.mode\""), true)
        let currentTools = runtime.get("currentTools").getOrThrow().asArray().toJsonString()
        let effectiveTools = runtime.get("effectiveTools").getOrThrow().asArray().toJsonString()
        @Expect(currentTools.contains("\"process\""), true)
        @Expect(currentTools.contains("\"gateway\""), true)
        @Expect(effectiveTools.contains("\"process\""), true)
        @Expect(effectiveTools.contains("\"gateway\""), true)
        let missingExtended = runtime.get("missingExtendedSurfaceTools").getOrThrow().asArray()
        let missingNames = ArrayList<String>()
        for (i in 0..missingExtended.size()) {
            try {
                missingNames.add(missingExtended[i].asString().getValue().trimAscii())
            } catch (_: Exception) {
                ()
            }
        }
        @Expect(missingNames.contains("cron"), false)
        @Expect(missingNames.contains("process"), false)
        @Expect(missingNames.contains("gateway"), false)
        @Expect(missingNames.contains("message"), false)
        @Expect(missingNames.contains("sessions_spawn"), false)
        @Expect(missingNames.contains("subagents"), false)
        let ingresses = runtime.get("ingresses").getOrThrow().asArray()
        @Expect(ingresses.size() >= 5, true)
        let firstTools = ingresses[0].asObject().get("tools").getOrThrow().asArray().toJsonString()
        let firstEffectiveTools = ingresses[0].asObject().get("effectiveTools").getOrThrow().asArray().toJsonString()
        var qqCaps = ""
        var feishuCaps = ""
        var controlUiCaps = ""
        var firstPromptProfile = ""
        for (i in 0..ingresses.size()) {
            let row = ingresses[i].asObject()
            @Expect(row.get("sharesGatewayMainRuntime").getOrThrow().asBool().getValue(), true)
            @Expect(agentsTestString(row, "runtime"), "gateway-main")
            @Expect(agentsTestString(row, "agent"), "GatewayP1ChatAgent")
            @Expect(row.get("coversUnifiedCoreBaseline").getOrThrow().asBool().getValue(), true)
            @Expect(row.get("capabilities").isSome(), true)
            @Expect(agentsTestString(row, "capabilityScope"), "delivery-only")
            @Expect(row.get("tools").getOrThrow().asArray().toJsonString(), firstTools)
            @Expect(row.get("effectiveTools").getOrThrow().asArray().toJsonString(), firstEffectiveTools)
            @Expect(row.get("promptProfile").isSome(), true)
            @Expect(row.get("authorizationProfile").isSome(), true)
            let promptProfile = row.get("promptProfile").getOrThrow().asObject()
            @Expect(agentsTestString(promptProfile, "template"), "gateway-im-metis-runtime")
            @Expect(promptProfile.get("sharedBasePrompt").getOrThrow().asBool().getValue(), true)
            let differsOnlyBy = promptProfile.get("differsOnlyBy").getOrThrow().asArray().toJsonString()
            if (firstPromptProfile.isEmpty()) {
                firstPromptProfile = promptProfile.toJsonString()
            } else {
                @Expect(promptProfile.toJsonString(), firstPromptProfile)
            }
            @Expect(differsOnlyBy.contains("\"channel-label\""), true)
            @Expect(differsOnlyBy.contains("\"delivery-capabilities\""), true)
            let rowAuthorizationProfile = row.get("authorizationProfile").getOrThrow().asObject()
            @Expect(agentsTestString(rowAuthorizationProfile, "authorizationModel"), "policy-gated")
            @Expect(rowAuthorizationProfile.toJsonString(), authorizationProfile.toJsonString())
            let ingressId = agentsTestString(row, "id")
            let capsText = row.get("capabilities").getOrThrow().asArray().toJsonString()
            if (ingressId == "qq") {
                qqCaps = capsText
            } else if (ingressId == "feishu") {
                feishuCaps = capsText
            } else if (ingressId == "control-ui") {
                controlUiCaps = capsText
            }
        }
        @Expect(qqCaps.contains("\"message-reply\""), true)
        @Expect(qqCaps.contains("\"thread-reply\""), false)
        @Expect(feishuCaps.contains("\"thread-reply\""), true)
        @Expect(controlUiCaps.contains("\"message-reply\""), true)
        @Expect(controlUiCaps.contains("\"thread-reply\""), true)
    }

    @TestCase
    public func dashboardAgentsRuntimeReusesUnifiedGatewayMainRuntimeProfile(): Unit {
        let response = handleGatewayDashboardFamily("dashboard.agents.runtime", GatewayRpcRequest("dashboard.agents.runtime")).getOrThrow()
        @Expect(response.ok, true)
        let result = response.result.asObject()
        let runtime = result.get("runtime").getOrThrow().asObject()
        @Expect(agentsTestString(runtime, "kind"), "gateway-main-runtime-profile")
        @Expect(runtime.get("coversUnifiedCoreBaseline").getOrThrow().asBool().getValue(), true)
        @Expect(runtime.get("effectiveTools").isSome(), true)
        @Expect(runtime.get("authorizationProfile").isSome(), true)
        let ingresses = runtime.get("ingresses").getOrThrow().asArray()
        @Expect(ingresses.size() >= 5, true)
        let firstPromptProfile = ingresses[0].asObject().get("promptProfile").getOrThrow().asObject()
        @Expect(agentsTestString(firstPromptProfile, "template"), "gateway-im-metis-runtime")
        @Expect(firstPromptProfile.get("sharedBasePrompt").getOrThrow().asBool().getValue(), true)
        let firstAuthorizationProfile = ingresses[0].asObject().get("authorizationProfile").getOrThrow().asObject()
        @Expect(agentsTestString(firstAuthorizationProfile, "enforcementStage"), "runtime-tool-filter")
    }

    @TestCase
    public func agentsRuntimeProfileReflectsPolicyRestrictedToolsWithoutHidingRegistration(): Unit {
        let original = CliSettingManager.setting.gateway
        try {
            var updated = original
            updated.tools.allow = []
            updated.tools.deny = ["shellExecute", "process", "gateway", "message", "subagents"]
            CliSettingManager.setting.gateway = updated

            let response = handleGatewayAgentsFamily("agents.runtime.profile").getOrThrow()
            @Expect(response.ok, true)
            let runtime = response.result.asObject().get("runtime").getOrThrow().asObject()
            let authorizationProfile = runtime.get("authorizationProfile").getOrThrow().asObject()
            let currentTools = runtime.get("currentTools").getOrThrow().asArray().toJsonString()
            let effectiveTools = runtime.get("effectiveTools").getOrThrow().asArray().toJsonString()
            let authorizedTools = authorizationProfile.get("authorizedTools").getOrThrow().asArray().toJsonString()
            let restrictedTools = authorizationProfile.get("restrictedTools").getOrThrow().asArray().toJsonString()

            @Expect(currentTools.contains("\"shellExecute\""), true)
            @Expect(currentTools.contains("\"process\""), true)
            @Expect(currentTools.contains("\"gateway\""), true)
            @Expect(currentTools.contains("\"message\""), true)
            @Expect(currentTools.contains("\"subagents\""), true)

            @Expect(authorizedTools.contains("\"shellExecute\""), false)
            @Expect(authorizedTools.contains("\"process\""), false)
            @Expect(authorizedTools.contains("\"gateway\""), false)
            @Expect(authorizedTools.contains("\"message\""), false)
            @Expect(authorizedTools.contains("\"subagents\""), false)
            @Expect(effectiveTools.contains("\"shellExecute\""), false)
            @Expect(effectiveTools.contains("\"process\""), false)
            @Expect(effectiveTools.contains("\"gateway\""), false)
            @Expect(effectiveTools.contains("\"message\""), false)
            @Expect(effectiveTools.contains("\"subagents\""), false)

            @Expect(restrictedTools.contains("\"shellExecute\""), true)
            @Expect(restrictedTools.contains("\"process\""), true)
            @Expect(restrictedTools.contains("\"gateway\""), true)
            @Expect(restrictedTools.contains("\"message\""), true)
            @Expect(restrictedTools.contains("\"subagents\""), true)
            @Expect(agentsTestString(authorizationProfile, "rejectionContract"), "deny-with-reason")
            @Expect(agentsTestString(authorizationProfile, "enforcementStage"), "runtime-tool-filter")
        } finally {
            CliSettingManager.setting.gateway = original
        }
    }

    @TestCase
    public func agentsRuntimeAuditSummarizesUnifiedGatewayMainRuntimeClosure(): Unit {
        let response = handleGatewayAgentsFamily("agents.runtime.audit").getOrThrow()
        @Expect(response.ok, true)
        let audit = response.result.asObject().get("audit").getOrThrow().asObject()
        @Expect(agentsTestString(audit, "kind"), "gateway-main-runtime-audit")
        let summary = audit.get("summary").getOrThrow().asObject()
        @Expect(agentsTestString(summary, "phase"), "G8")
        @Expect(agentsTestString(summary, "defaultRuntime"), "gateway-main")
        @Expect(agentsTestString(summary, "defaultAgent"), "GatewayP1ChatAgent")
        @Expect(agentsTestString(summary, "embeddedMode"), "explicit-local-fallback")
        @Expect(summary.get("embeddedIsPrimary").getOrThrow().asBool().getValue(), false)
        let closure = summary.get("closure").getOrThrow().asObject()
        @Expect(closure.get("defaultIngressesShareGatewayMain").getOrThrow().asBool().getValue(), true)
        @Expect(closure.get("policyFilteringEnforcedAtRuntime").getOrThrow().asBool().getValue(), true)
        @Expect(closure.get("gatewayActionPolicyExposedAcrossConsumers").getOrThrow().asBool().getValue(), true)
        @Expect(closure.get("gatewayOwnerAndExplicitInferenceUsesRuntimeContext").getOrThrow().asBool().getValue(), true)
        @Expect(closure.get("gatewayActionPolicyUsesOperatorScopesAndDeclaredUser").getOrThrow().asBool().getValue(), true)
        let consumers = summary.get("consumers").getOrThrow().asObject()
        @Expect(consumers.get("dashboardAgentsRuntimeAudit").getOrThrow().asBool().getValue(), true)
        @Expect(consumers.get("controlUiWsAudit").getOrThrow().asBool().getValue(), true)
        @Expect(summary.get("acceptanceCount").getOrThrow().asInt().getValue(), 8)
        @Expect(summary.get("remainingCount").getOrThrow().asInt().getValue(), 4)
        let acceptance = audit.get("acceptance").getOrThrow().asArray().toJsonString()
        @Expect(acceptance.contains("\"default-ingresses-share-gateway-main\""), true)
        @Expect(acceptance.contains("\"embedded-local-is-fallback-only\""), true)
        @Expect(acceptance.contains("\"audit-consumers-share-the-same-closure-surface\""), true)
        @Expect(acceptance.contains("\"gateway-action-policy-is-visible-across-runtime-consumers\""), true)
        @Expect(acceptance.contains("\"gateway-owner-and-explicit-inference-use-runtime-context\""), true)
        @Expect(acceptance.contains("\"gateway-owner-inference-consumes-operator-scopes-and-declared-user\""), true)
        let runtime = audit.get("runtime").getOrThrow().asObject()
        @Expect(runtime.get("effectiveTools").isSome(), true)
        @Expect(runtime.get("authorizationProfile").isSome(), true)
        let authorizationProfile = runtime.get("authorizationProfile").getOrThrow().asObject()
        @Expect(authorizationProfile.get("gatewayActionPolicy").isSome(), true)
        let effectiveTools = runtime.get("effectiveTools").getOrThrow().asArray().toJsonString()
        @Expect(effectiveTools.contains("\"process\""), true)
        @Expect(effectiveTools.contains("\"gateway\""), true)
        let remaining = audit.get("remaining").getOrThrow().asArray().toJsonString()
        @Expect(remaining.contains("deeper control surfaces"), true)
        @Expect(remaining.contains("approval-surface callbacks"), true)
        let remainingSummary = audit.get("remainingSummary").getOrThrow().asObject()
        @Expect(remainingSummary.get("managedSessionAndAcpConvergence").getOrThrow().asBool().getValue(), true)
    }

    @TestCase
    public func dashboardAgentsRuntimeAuditReusesUnifiedClosureSurface(): Unit {
        let response = handleGatewayDashboardFamily("dashboard.agents.runtime.audit", GatewayRpcRequest("dashboard.agents.runtime.audit")).getOrThrow()
        @Expect(response.ok, true)
        let audit = response.result.asObject().get("audit").getOrThrow().asObject()
        @Expect(agentsTestString(audit, "kind"), "gateway-main-runtime-audit")
        let summary = audit.get("summary").getOrThrow().asObject()
        @Expect(agentsTestString(summary, "phase"), "G8")
        let consumers = summary.get("consumers").getOrThrow().asObject()
        @Expect(consumers.get("dashboardAgentsRuntimeAudit").getOrThrow().asBool().getValue(), true)
        let runtime = audit.get("runtime").getOrThrow().asObject()
        @Expect(runtime.get("effectiveTools").isSome(), true)
        @Expect(runtime.get("authorizationProfile").isSome(), true)
    }

    @TestCase
    public func agentsAddBootstrapsWorkspaceAgentDirAndSessionsWithoutAuthCopy(): Unit {
        withAgentsTempHome("metis-agents-add-phase5-home", { home =>
            let params = JsonObject()
            params.put("id", JsonString("pm"))
            params.put("name", JsonString("Project Manager"))
            let response = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: params))).getOrThrow()
            @Expect(response.ok, true)
            let result = response.result.asObject()
            let workspaceDir = home.join("workspaces").join("pm")
            let agentDir = home.join("agents").join("pm").join("agent")
            let sessionsDir = home.join("agents").join("pm").join("sessions")

            @Expect(agentsTestString(result, "workspaceDir"), workspaceDir.toString())
            @Expect(agentsTestString(result, "agentDir"), agentDir.toString())
            @Expect(agentsTestString(result, "sessionsDir"), sessionsDir.toString())
            @Expect(exists(agentDir.join("AGENT.md")), true)
            @Expect(exists(agentDir.join("models.json")), false)
            @Expect(exists(agentDir.join("auth-profiles.json")), false)
            @Expect(exists(sessionsDir), true)
            for (name in ["AGENTS.md", "SOUL.md", "TOOLS.md", "IDENTITY.md", "USER.md", "HEARTBEAT.md", "MEMORY.md"]) {
                @Expect(exists(workspaceDir.join(name)), true)
            }

            let bootstrap = result.get("bootstrap").getOrThrow().asObject()
            @Expect(agentsTestBool(bootstrap, "authProfilesCopied"), false)
            @Expect(agentsTestBool(bootstrap, "authProfilesCopyRequiresExplicitRequest"), true)
            @Expect(bootstrap.get("files").getOrThrow().asArray().size() >= 7, true)

            let root = MetisConfigManager.rawConfig().getOrThrow()
            let entries = root.get("agents").getOrThrow().asObject().get("list").getOrThrow().asArray()
            var configuredAgentDir = ""
            for (i in 0..entries.size()) {
                let row = entries[i].asObject()
                if (agentsTestString(row, "id") == "pm") {
                    configuredAgentDir = agentsTestString(row, "agentDir")
                }
            }
            @Expect(configuredAgentDir, agentDir.toString())
        })
    }

    @TestCase
    public func agentsAddRejectsBuiltinAgentIdWithSpecificMessage(): Unit {
        withAgentsTempHome("metis-agents-add-builtin-id-home", { _home: Path =>
            let params = JsonObject()
            params.put("id", JsonString("reviewer"))
            params.put("name", JsonString("Reviewer"))

            let response = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: params))).getOrThrow()

            @Expect(response.ok, false)
            @Expect(response.error.contains("builtin agent"), true)
            @Expect(response.error.contains("cannot be recreated"), true)
        })
    }

    @TestCase
    public func agentsDeleteRejectsBuiltinAgentIdWithSpecificMessage(): Unit {
        withAgentsTempHome("metis-agents-delete-builtin-id-home", { _home: Path =>
            let params = JsonObject()
            params.put("agentId", JsonString("reviewer"))

            let response = handleGatewayAgentsFamily("agents.delete", request: Some(GatewayRpcRequest("agents.delete", params: params))).getOrThrow()

            @Expect(response.ok, false)
            @Expect(response.error.contains("builtin agent"), true)
            @Expect(response.error.contains("cannot be deleted"), true)
        })
    }

    @TestCase
    public func agentsAddDoesNotOverwriteExistingWorkspaceIdentityFile(): Unit {
        withAgentsTempHome("metis-agents-add-phase5-existing-home", { home =>
            let workspaceDir = home.join("custom-workspace")
            Directory.create(workspaceDir, recursive: true)
            File.writeTo(workspaceDir.join("IDENTITY.md"), "Name: Existing\n".toArray())

            let params = JsonObject()
            params.put("id", JsonString("writer"))
            params.put("workspace", JsonString(workspaceDir.toString()))
            let response = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: params))).getOrThrow()
            @Expect(response.ok, true)

            @Expect(String.fromUtf8(File.readFrom(workspaceDir.join("IDENTITY.md"))), "Name: Existing\n")
            @Expect(exists(workspaceDir.join("AGENTS.md")), true)
            @Expect(exists(workspaceDir.join("MEMORY.md")), true)
        })
    }

    @TestCase
    public func agentsAddRejectsDuplicateAgentDirWithoutPartialConfig(): Unit {
        withAgentsTempHome("metis-agents-add-duplicate-agentdir-home", { home: Path =>
            let firstParams = JsonObject()
            firstParams.put("id", JsonString("writer"))
            let first = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: firstParams))).getOrThrow()
            @Expect(first.ok, true)
            let sharedAgentDir = home.join("agents").join("writer").join("agent").toString()
            let before = MetisConfigManager.rawConfig().getOrThrow().toJsonString()

            let duplicateParams = JsonObject()
            duplicateParams.put("id", JsonString("qa"))
            duplicateParams.put("agentDir", JsonString(sharedAgentDir))
            let duplicate = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: duplicateParams))).getOrThrow()

            @Expect(duplicate.ok, false)
            @Expect(duplicate.error.contains("Duplicate agentDir"), true)
            @Expect(MetisConfigManager.rawConfig().getOrThrow().toJsonString(), before)
            @Expect(agentsTestConfiguredAgent(MetisConfigManager.rawConfig().getOrThrow(), "qa").size(), 0)
            @Expect(exists(home.join("workspaces").join("qa")), false)
            @Expect(exists(home.join("agents").join("qa")), false)
        })
    }

    @TestCase
    public func agentsAddWritesTelegramFeishuQqAccountsAndAutoBindingsRedacted(): Unit {
        withAgentsTempHome("metis-agents-add-channel-credentials-home", { _home: Path =>
            let seed = JsonObject()
            let gateway = JsonObject()
            let telegramCfg = JsonObject()
            telegramCfg.put("defaultAccount", JsonString("primary-tg"))
            gateway.put("telegram", telegramCfg)
            let feishuCfg = JsonObject()
            feishuCfg.put("defaultAccount", JsonString("primary-fs"))
            gateway.put("feishu", feishuCfg)
            seed.put("gateway", gateway)
            MetisConfigManager.writeRoot(seed)

            let params = JsonObject()
            params.put("id", JsonString("writer"))
            params.put("model", JsonString("dashscope:qwen-test"))
            let credentials = JsonObject()
            let telegram = JsonObject()
            telegram.put("accountId", JsonString("bot-a"))
            telegram.put("botToken", JsonString("123456:test-telegram-token-never-visible"))
            credentials.put("telegram", telegram)
            let feishu = JsonObject()
            feishu.put("accountId", JsonString("fs-a"))
            feishu.put("appId", JsonString("cli_test_app"))
            feishu.put("appSecret", JsonString("test-feishu-secret-never-visible"))
            credentials.put("feishu", feishu)
            let qq = JsonObject()
            qq.put("accountId", JsonString("qq-a"))
            qq.put("appId", JsonString("102012345"))
            qq.put("appSecret", JsonString("test-qq-secret-never-visible"))
            credentials.put("qq", qq)
            params.put("channelCredentials", credentials)
            let explicit = JsonArray([])
            explicit.add(JsonString("telegram:bot-a"))
            params.put("bind", explicit)

            let response = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: params))).getOrThrow()
            @Expect(response.ok, true)
            let resultText = response.result.toJsonString()
            @Expect(resultText.contains("test-telegram-token-never-visible"), false)
            @Expect(resultText.contains("test-feishu-secret-never-visible"), false)
            @Expect(resultText.contains("test-qq-secret-never-visible"), false)
            @Expect(resultText.contains("configPreview"), false)

            let result = response.result.asObject()
            let summaries = agentsTestArray(result, "channelAccounts")
            let tgSummary = agentsTestFindChannelAccountSummary(summaries, "telegram", "bot-a")
            let fsSummary = agentsTestFindChannelAccountSummary(summaries, "feishu", "fs-a")
            let qqSummary = agentsTestFindChannelAccountSummary(summaries, "qq", "qq-a")
            @Expect(agentsTestString(tgSummary, "action"), "created")
            @Expect(agentsTestString(tgSummary, "token"), "[redacted]")
            @Expect(agentsTestString(fsSummary, "action"), "created")
            @Expect(agentsTestString(fsSummary, "appId"), "cli_...")
            @Expect(agentsTestString(fsSummary, "appSecret"), "[redacted]")
            @Expect(agentsTestString(qqSummary, "action"), "created")
            @Expect(agentsTestString(qqSummary, "appId"), "1020...")
            @Expect(agentsTestString(qqSummary, "appSecret"), "[redacted]")

            let bindings = agentsTestObject(result, "bindings")
            @Expect(agentsTestArrayContains(agentsTestArray(bindings, "added"), "telegram:bot-a"), true)
            @Expect(agentsTestArrayContains(agentsTestArray(bindings, "added"), "feishu:fs-a"), true)
            @Expect(agentsTestArrayContains(agentsTestArray(bindings, "added"), "qq:qq-a"), true)
            @Expect(agentsTestArray(bindings, "skipped").size(), 0)

            let root = MetisConfigManager.rawConfig().getOrThrow()
            let tgAccount = agentsTestGatewayAccount(root, "telegram", "bot-a")
            let fsAccount = agentsTestGatewayAccount(root, "feishu", "fs-a")
            let qqAccount = agentsTestGatewayAccount(root, "qq", "qq-a")
            @Expect(agentsTestString(tgAccount, "botToken"), "123456:test-telegram-token-never-visible")
            @Expect(agentsTestString(fsAccount, "appId"), "cli_test_app")
            @Expect(agentsTestString(fsAccount, "appSecret"), "test-feishu-secret-never-visible")
            @Expect(agentsTestString(fsAccount, "dmPolicy"), "pairing")
            @Expect(agentsTestArray(fsAccount, "allowFrom").size(), 0)
            @Expect(agentsTestString(fsAccount, "groupPolicy"), "disabled")
            @Expect(agentsTestArray(fsAccount, "groupAllowFrom").size(), 0)
            @Expect(agentsTestObject(fsAccount, "groups").size(), 0)
            @Expect(agentsTestString(qqAccount, "appId"), "102012345")
            @Expect(agentsTestString(qqAccount, "appSecret"), "test-qq-secret-never-visible")
            @Expect(agentsTestString(agentsTestObject(agentsTestObject(root, "gateway"), "telegram"), "defaultAccount"), "primary-tg")
            @Expect(agentsTestString(agentsTestObject(agentsTestObject(root, "gateway"), "feishu"), "defaultAccount"), "primary-fs")
            let agentEntry = agentsTestConfiguredAgent(root, "writer")
            @Expect(agentEntry.get("telegram").isSome(), false)
            @Expect(agentEntry.get("feishu").isSome(), false)
            @Expect(agentEntry.get("qq").isSome(), false)
            @Expect(root.toJsonString().contains("agentAccounts"), false)
        })
    }

    @TestCase
    public func agentsAddRejectsDifferentExistingChannelAccountWithoutPartialWrite(): Unit {
        withAgentsTempHome("metis-agents-add-channel-conflict-home", { home: Path =>
            let seed = JsonObject()
            let gateway = JsonObject()
            let feishuCfg = JsonObject()
            let accounts = JsonObject()
            let existing = JsonObject()
            existing.put("appId", JsonString("cli_test_app"))
            existing.put("appSecret", JsonString("existing-feishu-secret"))
            accounts.put("shared", existing)
            feishuCfg.put("accounts", accounts)
            gateway.put("feishu", feishuCfg)
            seed.put("gateway", gateway)
            MetisConfigManager.writeRoot(seed)
            let before = MetisConfigManager.rawConfig().getOrThrow().toJsonString()

            let params = JsonObject()
            params.put("id", JsonString("writer"))
            let credentials = JsonObject()
            let feishu = JsonObject()
            feishu.put("accountId", JsonString("shared"))
            feishu.put("appId", JsonString("cli_test_app"))
            feishu.put("appSecret", JsonString("test-feishu-secret-never-visible"))
            credentials.put("feishu", feishu)
            params.put("channelCredentials", credentials)

            let response = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: params))).getOrThrow()
            @Expect(response.ok, false)
            @Expect(response.error.contains("feishu account \"shared\""), true)
            @Expect(response.error.contains("test-feishu-secret-never-visible"), false)
            @Expect(MetisConfigManager.rawConfig().getOrThrow().toJsonString(), before)
            @Expect(agentsTestConfiguredAgent(MetisConfigManager.rawConfig().getOrThrow(), "writer").size(), 0)
            @Expect(exists(home.join("agents").join("writer")), false)
            @Expect(exists(home.join("workspaces").join("writer")), false)
        })
    }

    @TestCase
    public func agentsAddOverwritesExistingChannelAccountWhenRequested(): Unit {
        withAgentsTempHome("metis-agents-add-channel-overwrite-home", { _home: Path =>
            let seed = JsonObject()
            let gateway = JsonObject()
            let telegramCfg = JsonObject()
            let accounts = JsonObject()
            let existing = JsonObject()
            existing.put("botToken", JsonString("123456:old-token"))
            accounts.put("shared", existing)
            telegramCfg.put("accounts", accounts)
            gateway.put("telegram", telegramCfg)
            seed.put("gateway", gateway)
            MetisConfigManager.writeRoot(seed)

            let params = JsonObject()
            params.put("id", JsonString("writer"))
            params.put("channelOverwrite", JsonBool(true))
            let credentials = JsonObject()
            let telegram = JsonObject()
            telegram.put("accountId", JsonString("shared"))
            telegram.put("botToken", JsonString("123456:test-telegram-token-never-visible"))
            credentials.put("telegram", telegram)
            params.put("channelCredentials", credentials)

            let response = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: params))).getOrThrow()
            @Expect(response.ok, true)
            @Expect(response.result.toJsonString().contains("test-telegram-token-never-visible"), false)
            let summaries = agentsTestArray(response.result.asObject(), "channelAccounts")
            let tgSummary = agentsTestFindChannelAccountSummary(summaries, "telegram", "shared")
            @Expect(agentsTestString(tgSummary, "action"), "updated")
            let root = MetisConfigManager.rawConfig().getOrThrow()
            @Expect(agentsTestString(agentsTestGatewayAccount(root, "telegram", "shared"), "botToken"), "123456:test-telegram-token-never-visible")
        })
    }

    @TestCase
    public func agentsAddBindingConflictDoesNotPersistAgentOrCredential(): Unit {
        withAgentsTempHome("metis-agents-add-channel-binding-conflict-home", { home: Path =>
            @Expect(agentsTestAddAgent("owner").ok, true)
            let bindParams = JsonObject()
            bindParams.put("agentId", JsonString("owner"))
            bindParams.put("bind", JsonString("telegram:shared"))
            let bindResponse = handleGatewayAgentsFamily("agents.bind", request: Some(GatewayRpcRequest("agents.bind", params: bindParams))).getOrThrow()
            @Expect(bindResponse.ok, true)
            let before = MetisConfigManager.rawConfig().getOrThrow().toJsonString()

            let params = JsonObject()
            params.put("id", JsonString("writer"))
            let credentials = JsonObject()
            let telegram = JsonObject()
            telegram.put("accountId", JsonString("shared"))
            telegram.put("botToken", JsonString("123456:test-telegram-token-never-visible"))
            credentials.put("telegram", telegram)
            params.put("channelCredentials", credentials)

            let response = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: params))).getOrThrow()
            @Expect(response.ok, false)
            @Expect(response.error.contains("telegram:shared"), true)
            @Expect(response.error.contains("test-telegram-token-never-visible"), false)
            @Expect(response.result.toJsonString().contains("configPreview"), false)
            @Expect(MetisConfigManager.rawConfig().getOrThrow().toJsonString(), before)
            @Expect(agentsTestConfiguredAgent(MetisConfigManager.rawConfig().getOrThrow(), "writer").size(), 0)
            @Expect(agentsTestGatewayAccount(MetisConfigManager.rawConfig().getOrThrow(), "telegram", "shared").size(), 0)
            @Expect(exists(home.join("agents").join("writer")), false)
        })
    }

    @TestCase
    public func agentsAddReusesSameExistingChannelAccountAndWritesQqCredential(): Unit {
        withAgentsTempHome("metis-agents-add-channel-reuse-qq-home", { _home: Path =>
            let seed = JsonObject()
            let gateway = JsonObject()
            let feishuCfg = JsonObject()
            let accounts = JsonObject()
            let existing = JsonObject()
            existing.put("appId", JsonString("cli_test_app"))
            existing.put("appSecret", JsonString("test-feishu-secret-never-visible"))
            accounts.put("shared", existing)
            feishuCfg.put("accounts", accounts)
            gateway.put("feishu", feishuCfg)
            seed.put("gateway", gateway)
            MetisConfigManager.writeRoot(seed)

            let params = JsonObject()
            params.put("id", JsonString("writer"))
            let credentials = JsonObject()
            let feishu = JsonObject()
            feishu.put("accountId", JsonString("shared"))
            feishu.put("appId", JsonString("cli_test_app"))
            feishu.put("appSecret", JsonString("test-feishu-secret-never-visible"))
            credentials.put("feishu", feishu)
            params.put("channelCredentials", credentials)

            let response = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: params))).getOrThrow()
            @Expect(response.ok, true)
            @Expect(response.result.toJsonString().contains("test-feishu-secret-never-visible"), false)
            let fsSummary = agentsTestFindChannelAccountSummary(agentsTestArray(response.result.asObject(), "channelAccounts"), "feishu", "shared")
            @Expect(agentsTestString(fsSummary, "action"), "reused")

            let qqParams = JsonObject()
            qqParams.put("id", JsonString("qq-writer"))
            let qqCredentials = JsonObject()
            let qq = JsonObject()
            qq.put("accountId", JsonString("qq-a"))
            qq.put("appId", JsonString("1020"))
            qq.put("appSecret", JsonString("test-qq-secret-never-visible"))
            qqCredentials.put("qq", qq)
            qqParams.put("channelCredentials", qqCredentials)
            let qqResponse = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: qqParams))).getOrThrow()
            @Expect(qqResponse.ok, true)
            @Expect(qqResponse.result.toJsonString().contains("test-qq-secret-never-visible"), false)
            let qqSummary = agentsTestFindChannelAccountSummary(agentsTestArray(qqResponse.result.asObject(), "channelAccounts"), "qq", "qq-a")
            @Expect(agentsTestString(qqSummary, "action"), "created")
            let root = MetisConfigManager.rawConfig().getOrThrow()
            @Expect(agentsTestString(agentsTestGatewayAccount(root, "qq", "qq-a"), "appId"), "1020")
            @Expect(agentsTestString(agentsTestGatewayAccount(root, "qq", "qq-a"), "appSecret"), "test-qq-secret-never-visible")
            let bindings = agentsTestObject(qqResponse.result.asObject(), "bindings")
            @Expect(agentsTestArrayContains(agentsTestArray(bindings, "added"), "qq:qq-a"), true)
        })
    }

    @TestCase
    public func agentsBindAppliesFullRouteBindingsAndPreservesNonRouteRows(): Unit {
        withAgentsTempHome("metis-agents-bind-route-apply-home", { _home: Path =>
            @Expect(agentsTestAddAgent("assistant-a").ok, true)
            @Expect(agentsTestAddAgent("critic").ok, true)

            let root = MetisConfigManager.rawConfig().getOrThrow()
            let seedBindings = JsonArray([])
            let nonRoute = JsonObject()
            nonRoute.put("type", JsonString("token"))
            nonRoute.put("name", JsonString("preserve-me"))
            seedBindings.add(nonRoute)
            root.put("bindings", seedBindings)
            MetisConfigManager.writeRoot(root)

            let legacyParams = JsonObject()
            legacyParams.put("agentId", JsonString("assistant-a"))
            legacyParams.put("bind", JsonString("telegram"))
            let legacyResponse = handleGatewayAgentsFamily("agents.bind", request: Some(GatewayRpcRequest("agents.bind", params: legacyParams))).getOrThrow()
            @Expect(legacyResponse.ok, true)
            @Expect(legacyResponse.result.asObject().get("added").getOrThrow().asArray().size(), 1)

            let upgradeParams = JsonObject()
            upgradeParams.put("agentId", JsonString("assistant-a"))
            upgradeParams.put("bind", JsonString("telegram:bot-a"))
            let upgradeResponse = handleGatewayAgentsFamily("agents.bind", request: Some(GatewayRpcRequest("agents.bind", params: upgradeParams))).getOrThrow()
            @Expect(upgradeResponse.ok, true)
            let upgradeResult = upgradeResponse.result.asObject()
            @Expect(upgradeResult.get("updated").getOrThrow().asArray().size(), 1)
            @Expect(upgradeResult.get("added").getOrThrow().asArray().size(), 0)

            let conflictBindings = JsonArray([])
            conflictBindings.add(agentsTestRouteBinding("critic", "telegram", accountId: "bot-a"))
            let conflictParams = JsonObject()
            conflictParams.put("agentId", JsonString("critic"))
            conflictParams.put("bindings", conflictBindings)
            let conflictResponse = handleGatewayAgentsFamily("agents.bind", request: Some(GatewayRpcRequest("agents.bind", params: conflictParams))).getOrThrow()
            @Expect(conflictResponse.ok, true)
            let conflictResult = conflictResponse.result.asObject()
            @Expect(conflictResult.get("conflicts").getOrThrow().asArray().size(), 1)
            @Expect(conflictResult.get("added").getOrThrow().asArray().size(), 0)

            let persisted = agentsTestRawBindings()
            @Expect(persisted.size(), 2)
            @Expect(persisted[0].asObject().get("type").getOrThrow().asString().getValue(), "token")
            @Expect(persisted.toJsonString().contains("\"agentId\":\"critic\""), false)
        })
    }

    @TestCase
    public func agentsBindAndUnbindSupportThreadPeerMatch(): Unit {
        withAgentsTempHome("metis-agents-thread-binding-home", { _home: Path =>
            @Expect(agentsTestAddAgent("writer").ok, true)
            @Expect(agentsTestAddAgent("critic").ok, true)

            let bindings = JsonArray([])
            bindings.add(agentsTestRouteBinding("writer", "feishu", accountId: "tenant-a", peerKind: "thread", peerId: "thread-42"))
            let bindParams = JsonObject()
            bindParams.put("agentId", JsonString("writer"))
            bindParams.put("bindings", bindings)
            let bindResponse = handleGatewayAgentsFamily("agents.bind", request: Some(GatewayRpcRequest("agents.bind", params: bindParams))).getOrThrow()
            @Expect(bindResponse.ok, true)
            @Expect(bindResponse.result.asObject().get("added").getOrThrow().asArray().size(), 1)

            let route = gatewayResolveAgentRoute(GatewayAgentRouteInput(
                MetisConfigManager.rawConfig().getOrThrow(),
                "feishu",
                accountId: "tenant-a",
                peerKind: "thread",
                peerId: "thread-42",
                parentPeerKind: "group",
                parentPeerId: "chat-1"
            ))
            @Expect(route.agentId, "writer")
            @Expect(route.matchedBy, "binding.peer.exact")

            let conflictParams = JsonObject()
            conflictParams.put("agentId", JsonString("critic"))
            let conflictBindings = JsonArray([])
            conflictBindings.add(agentsTestRouteBinding("critic", "feishu", accountId: "tenant-a", peerKind: "thread", peerId: "thread-42"))
            conflictParams.put("bindings", conflictBindings)
            let conflictResponse = handleGatewayAgentsFamily("agents.unbind", request: Some(GatewayRpcRequest("agents.unbind", params: conflictParams))).getOrThrow()
            @Expect(conflictResponse.ok, true)
            @Expect(conflictResponse.result.asObject().get("conflicts").getOrThrow().asArray().size(), 1)
            @Expect(agentsTestRawBindings().size(), 1)

            let unbindParams = JsonObject()
            unbindParams.put("agentId", JsonString("writer"))
            unbindParams.put("bindings", bindings)
            let unbindResponse = handleGatewayAgentsFamily("agents.unbind", request: Some(GatewayRpcRequest("agents.unbind", params: unbindParams))).getOrThrow()
            @Expect(unbindResponse.ok, true)
            @Expect(unbindResponse.result.asObject().get("removed").getOrThrow().asArray().size(), 1)
            @Expect(unbindResponse.result.asObject().get("missing").getOrThrow().asArray().size(), 0)

            let missingResponse = handleGatewayAgentsFamily("agents.unbind", request: Some(GatewayRpcRequest("agents.unbind", params: unbindParams))).getOrThrow()
            @Expect(missingResponse.ok, true)
            @Expect(missingResponse.result.asObject().get("removed").getOrThrow().asArray().size(), 0)
            @Expect(missingResponse.result.asObject().get("missing").getOrThrow().asArray().size(), 1)
        })
    }

    @TestCase
    public func managedAgentDirIsDiscoverableBySummaryAndSubagentResolver(): Unit {
        withAgentsTempHome("metis-agents-add-phase5-discovery-home", { home: Path =>
            let params = JsonObject()
            params.put("id", JsonString("pm"))
            params.put("name", JsonString("Project Manager"))
            let addResponse = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: params))).getOrThrow()
            @Expect(addResponse.ok, true)

            CliConfig.invalidatePathCache()
            let summaryResponse = handleGatewayAgentsFamily("agents.summary").getOrThrow()
            @Expect(summaryResponse.ok, true)
            let rows = summaryResponse.result.asObject().get("agents").getOrThrow().asObject().get("agents").getOrThrow().asArray()
            var sawPm = false
            var sawSyntheticAgent = false
            for (i in 0..rows.size()) {
                let row = rows[i].asObject()
                if (agentsTestString(row, "id") == "pm") {
                    sawPm = true
                    @Expect(agentsTestString(row, "kind"), "custom")
                    @Expect(agentsTestString(row, "workspace"), home.join("workspaces").join("pm").toString())
                }
                if (agentsTestString(row, "id") == "agent") {
                    sawSyntheticAgent = true
                }
            }
            @Expect(sawPm, true)
            @Expect(sawSyntheticAgent, false)

            let resolved = gatewaySubagentResolveAgent("pm")
            @Expect(resolved.found, true)
            @Expect(resolved.agentId, "pm")
            @Expect(resolved.agentDir, home.join("agents").join("pm").join("agent").toString())
        })
    }

    @TestCase
    public func agentModelRuntimeStateIsLazyEnsuredUnderAgentDirOnly(): Unit {
        withAgentsTempHome("metis-agents-add-phase5-models-home", { home: Path =>
            let agentDir = home.join("agents").join("pm").join("agent")
            Directory.create(agentDir, recursive: true)
            @Expect(exists(agentDir.join("models.json")), false)
            @Expect(exists(home.join("models.json")), false)

            let path = CliModelRuntimeStateManager.ensureAgentRuntimeState(agentDir)

            @Expect(path.toString(), agentDir.join("models.json").toString())
            @Expect(exists(agentDir.join("models.json")), true)
            @Expect(exists(home.join("models.json")), false)
            let content = String.fromUtf8(File.readFrom(agentDir.join("models.json")))
            @Expect(content.contains("primaryModelRef"), true)
            @Expect(content.contains("token"), false)
            @Expect(content.contains("secret"), false)
        })
    }

    @TestCase
    public func agentsAddCopiesAuthProfilesOnlyWithExplicitSourceAndConfirm(): Unit {
        withAgentsTempHome("metis-agents-add-phase5-auth-copy-home", { home: Path =>
            File.writeTo(home.join("auth-profiles.json"), "{\"profiles\":[{\"id\":\"fixture\"}]}\n".toArray())

            let aliasParams = JsonObject()
            aliasParams.put("id", JsonString("alias"))
            aliasParams.put("copyAuthProfiles", true.toJsonValue())
            aliasParams.put("source", JsonString("global"))
            aliasParams.put("confirm", true.toJsonValue())
            let aliasDenied = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: aliasParams))).getOrThrow()
            @Expect(aliasDenied.ok, false)
            @Expect(aliasDenied.error.contains("default-agent"), true)
            @Expect(exists(home.join("agents").join("alias").join("agent").join("auth-profiles.json")), false)

            let deniedParams = JsonObject()
            deniedParams.put("id", JsonString("denied"))
            deniedParams.put("copyAuthProfiles", true.toJsonValue())
            deniedParams.put("source", JsonString("default-agent"))
            let denied = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: deniedParams))).getOrThrow()
            @Expect(denied.ok, false)
            @Expect(denied.error.contains("confirm"), true)
            @Expect(exists(home.join("agents").join("denied").join("agent").join("auth-profiles.json")), false)

            let params = JsonObject()
            params.put("id", JsonString("pm"))
            params.put("copyAuthProfiles", true.toJsonValue())
            params.put("source", JsonString("default-agent"))
            params.put("confirm", true.toJsonValue())
            let response = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: params))).getOrThrow()
            @Expect(response.ok, true)
            let target = home.join("agents").join("pm").join("agent").join("auth-profiles.json")
            @Expect(exists(target), true)
            @Expect(String.fromUtf8(File.readFrom(target)), "{\"profiles\":[{\"id\":\"fixture\"}]}\n")
            let bootstrap = response.result.asObject().get("bootstrap").getOrThrow().asObject()
            @Expect(agentsTestBool(bootstrap, "authProfilesCopied"), true)
        })
    }

    @TestCase
    public func agentsAddRefusesAuthProfileCopyOverwrite(): Unit {
        withAgentsTempHome("metis-agents-add-phase5-auth-overwrite-home", { home: Path =>
            File.writeTo(home.join("auth-profiles.json"), "{\"profiles\":[{\"id\":\"source\"}]}\n".toArray())
            let agentDir = home.join("agents").join("pm").join("agent")
            Directory.create(agentDir, recursive: true)
            File.writeTo(agentDir.join("auth-profiles.json"), "keep\n".toArray())

            let params = JsonObject()
            params.put("id", JsonString("pm"))
            params.put("agentDir", JsonString(agentDir.toString()))
            params.put("copyAuthProfiles", true.toJsonValue())
            params.put("source", JsonString("default-agent"))
            params.put("force", true.toJsonValue())
            let response = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: params))).getOrThrow()
            @Expect(response.ok, false)
            @Expect(response.error.contains("already exists"), true)
            @Expect(String.fromUtf8(File.readFrom(agentDir.join("auth-profiles.json"))), "keep\n")
        })
    }

    @TestCase
    public func agentsSetIdentityValidatesAvatarAgainstAgentWorkspace(): Unit {
        withAgentsTempHome("metis-agents-set-identity-avatar-home", { _: Path =>
            let addParams = JsonObject()
            addParams.put("id", JsonString("pm"))
            let addResponse = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: addParams))).getOrThrow()
            @Expect(addResponse.ok, true)

            let rejectedParams = JsonObject()
            rejectedParams.put("id", JsonString("pm"))
            rejectedParams.put("avatar", JsonString("../outside.png"))
            let rejected = handleGatewayAgentsFamily("agents.set-identity", request: Some(GatewayRpcRequest("agents.set-identity", params: rejectedParams))).getOrThrow()
            @Expect(rejected.ok, false)
            @Expect(rejected.error.contains("avatar"), true)

            let acceptedParams = JsonObject()
            acceptedParams.put("id", JsonString("pm"))
            acceptedParams.put("avatar", JsonString("HTTPS://example.test/avatar.png"))
            let accepted = handleGatewayAgentsFamily("agents.set-identity", request: Some(GatewayRpcRequest("agents.set-identity", params: acceptedParams))).getOrThrow()
            @Expect(accepted.ok, true)
            let identity = accepted.result.asObject().get("identity").getOrThrow().asObject()
            @Expect(agentsTestString(identity, "avatar"), "HTTPS://example.test/avatar.png")
        })
    }

    @TestCase
    public func agentsUpdateRoundTripsEditableConfigAndAliasDisplay(): Unit {
        withAgentsTempHome("metis-agents-update-phase7-home", { home: Path =>
            let addParams = JsonObject()
            addParams.put("id", JsonString("writer"))
            let addResponse = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: addParams))).getOrThrow()
            @Expect(addResponse.ok, true)

            let model = JsonObject()
            model.put("primary", JsonString("qwen:qwen-plus"))
            model.put("fallbacks", agentsTestStringArray(["openai:gpt-4o-mini"]))
            let groupChat = JsonObject()
            groupChat.put("mentionPatterns", agentsTestStringArray(["@writer", "/agent writer"]))
            let identity = JsonObject()
            identity.put("name", JsonString("Writer Prime"))
            identity.put("avatar", JsonString("https://example.test/writer.png"))

            let updateParams = JsonObject()
            updateParams.put("id", JsonString("writer"))
            updateParams.put("name", JsonString("Writer Prime"))
            updateParams.put("workspace", JsonString(home.join("team-workspace").toString()))
            updateParams.put("model", model)
            updateParams.put("groupChat", groupChat)
            updateParams.put("identity", identity)
            let updateResponse = handleGatewayAgentsFamily("agents.update", request: Some(GatewayRpcRequest("agents.update", params: updateParams))).getOrThrow()
            @Expect(updateResponse.ok, true)

            let getParams = JsonObject()
            getParams.put("agentId", JsonString("writer"))
            let getResponse = handleGatewayAgentsFamily("agent.get", request: Some(GatewayRpcRequest("agent.get", params: getParams))).getOrThrow()
            @Expect(getResponse.ok, true)
            let agent = getResponse.result.asObject().get("agent").getOrThrow().asObject()
            @Expect(agentsTestString(agent, "name"), "Writer Prime")
            @Expect(agentsTestString(agent, "workspace"), home.join("team-workspace").toString())
            @Expect(agentsTestString(agent.get("model").getOrThrow().asObject(), "primary"), "qwen:qwen-plus")
            let returnedGroupChat = agent.get("groupChat").getOrThrow().asObject()
            @Expect(agentsTestObjectArrayContainsString(returnedGroupChat, "mentionPatterns", "@writer"), true)
            @Expect(agentsTestObjectArrayContainsString(agent, "aliases", "/agent writer"), true)
            @Expect(exists(home.join("team-workspace").join("SOUL.md")), true)

            let listResponse = handleGatewayAgentsFamily("agents.list").getOrThrow()
            let rows = listResponse.result.asObject().get("agents").getOrThrow().asArray()
            let writer = agentsTestFindObjectById(rows, "writer")
            @Expect(agentsTestString(writer, "name"), "Writer Prime")
            @Expect(agentsTestObjectArrayContainsString(writer, "aliases", "@writer"), true)
        })
    }

    @TestCase
    public func agentsUpdateRejectsDuplicateAgentDirWithoutPartialConfig(): Unit {
        withAgentsTempHome("metis-agents-update-duplicate-agentdir-home", { home: Path =>
            @Expect(agentsTestAddAgent("writer").ok, true)
            @Expect(agentsTestAddAgent("qa").ok, true)
            let writerAgentDir = home.join("agents").join("writer").join("agent").toString()
            let qaAgentDir = home.join("agents").join("qa").join("agent").toString()
            let before = MetisConfigManager.rawConfig().getOrThrow().toJsonString()

            let updateParams = JsonObject()
            updateParams.put("id", JsonString("qa"))
            updateParams.put("agentDir", JsonString(writerAgentDir))
            updateParams.put("workspace", JsonString(home.join("workspaces").join("qa-updated").toString()))
            let update = handleGatewayAgentsFamily("agents.update", request: Some(GatewayRpcRequest("agents.update", params: updateParams))).getOrThrow()

            @Expect(update.ok, false)
            @Expect(update.error.contains("Duplicate agentDir"), true)
            @Expect(MetisConfigManager.rawConfig().getOrThrow().toJsonString(), before)
            let qa = agentsTestConfiguredAgent(MetisConfigManager.rawConfig().getOrThrow(), "qa")
            @Expect(agentsTestString(qa, "agentDir"), qaAgentDir)
            @Expect(exists(home.join("workspaces").join("qa-updated")), false)
        })
    }

    @TestCase
    public func agentFilesRpcUsesWorkspaceSafeBootstrapFiles(): Unit {
        withAgentsTempHome("metis-agents-files-phase7-home", { home: Path =>
            let addParams = JsonObject()
            addParams.put("id", JsonString("pm"))
            let addResponse = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: addParams))).getOrThrow()
            @Expect(addResponse.ok, true)
            let criticParams = JsonObject()
            criticParams.put("id", JsonString("critic"))
            let criticResponse = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: criticParams))).getOrThrow()
            @Expect(criticResponse.ok, true)

            let listParams = JsonObject()
            listParams.put("agentId", JsonString("pm"))
            let listResponse = handleGatewayAgentsFamily("agents.files.list", request: Some(GatewayRpcRequest("agents.files.list", params: listParams))).getOrThrow()
            @Expect(listResponse.ok, true)
            let listResult = listResponse.result.asObject()
            @Expect(agentsTestString(listResult, "workspace"), home.join("workspaces").join("pm").toString())
            let files = listResult.get("files").getOrThrow().asArray()
            @Expect(files.size(), 8)
            var presentProfileCount = 0
            var missingProfileCount = 0
            for (name in ["AGENTS.md", "SOUL.md", "TOOLS.md", "IDENTITY.md", "USER.md", "HEARTBEAT.md", "BOOTSTRAP.md", "MEMORY.md"]) {
                let row = agentsTestFindObjectById(files, name)
                @Expect(agentsTestString(row, "name"), name)
                if (name != "BOOTSTRAP.md") {
                    @Expect(agentsTestBool(row, "missing"), false)
                }
                if (agentsTestBool(row, "missing")) {
                    missingProfileCount += 1
                } else {
                    presentProfileCount += 1
                }
            }
            @Expect(presentProfileCount, 7)
            @Expect(missingProfileCount, 1)
            let bootstrapRow = agentsTestFindObjectById(files, "BOOTSTRAP.md")
            @Expect(agentsTestBool(bootstrapRow, "missing"), true)

            for (name in ["AGENTS.md", "SOUL.md", "TOOLS.md", "IDENTITY.md", "USER.md", "HEARTBEAT.md", "BOOTSTRAP.md", "MEMORY.md"]) {
                let setParams = JsonObject()
                setParams.put("agentId", JsonString("pm"))
                setParams.put("name", JsonString(name))
                setParams.put("content", JsonString("# ${name}\n\npm-only-${name}\n"))
                let setResponse = handleGatewayAgentsFamily("agents.files.set", request: Some(GatewayRpcRequest("agents.files.set", params: setParams))).getOrThrow()
                @Expect(setResponse.ok, true)
                let file = setResponse.result.asObject().get("file").getOrThrow().asObject()
                @Expect(agentsTestString(file, "content").contains("pm-only-${name}"), true)

                let getParams = JsonObject()
                getParams.put("agentId", JsonString("pm"))
                getParams.put("name", JsonString(name))
                let getResponse = handleGatewayAgentsFamily("agents.files.get", request: Some(GatewayRpcRequest("agents.files.get", params: getParams))).getOrThrow()
                @Expect(getResponse.ok, true)
                let readFile = getResponse.result.asObject().get("file").getOrThrow().asObject()
                @Expect(agentsTestString(readFile, "content").contains("pm-only-${name}"), true)
            }

            let crossReadParams = JsonObject()
            crossReadParams.put("agentId", JsonString("critic"))
            crossReadParams.put("name", JsonString("../pm/SOUL.md"))
            let crossRead = handleGatewayAgentsFamily("agents.files.get", request: Some(GatewayRpcRequest("agents.files.get", params: crossReadParams))).getOrThrow()
            @Expect(crossRead.ok, false)

            let crossWriteParams = JsonObject()
            crossWriteParams.put("agentId", JsonString("critic"))
            crossWriteParams.put("name", JsonString("../pm/SOUL.md"))
            crossWriteParams.put("content", JsonString("overwrite"))
            let crossWrite = handleGatewayAgentsFamily("agents.files.set", request: Some(GatewayRpcRequest("agents.files.set", params: crossWriteParams))).getOrThrow()
            @Expect(crossWrite.ok, false)
            @Expect(String.fromUtf8(File.readFrom(home.join("workspaces").join("pm").join("SOUL.md"))).contains("pm-only-SOUL.md"), true)

            let escapeParams = JsonObject()
            escapeParams.put("agentId", JsonString("pm"))
            escapeParams.put("name", JsonString("../outside.md"))
            escapeParams.put("content", JsonString("bad"))
            let escaped = handleGatewayAgentsFamily("agents.files.set", request: Some(GatewayRpcRequest("agents.files.set", params: escapeParams))).getOrThrow()
            @Expect(escaped.ok, false)
            @Expect(exists(home.join("workspaces").join("outside.md")), false)
        })
    }

    @TestCase
    public func agentAAgentBModelsRpcKeepsModelsJsonPathAndModelRefSeparate(): Unit {
        withAgentsTempHome("metis-agents-phase2-model-isolation-home", { home: Path =>
            let agentAParams = JsonObject()
            agentAParams.put("id", JsonString("agent-a"))
            agentAParams.put("model", JsonString("openai:gpt-4o-mini"))
            let agentAAdd = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: agentAParams))).getOrThrow()
            @Expect(agentAAdd.ok, true)

            let agentBParams = JsonObject()
            agentBParams.put("id", JsonString("agent-b"))
            agentBParams.put("model", JsonString("dashscope:qwen-plus"))
            let agentBAdd = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: agentBParams))).getOrThrow()
            @Expect(agentBAdd.ok, true)

            let agentAState = JsonObject()
            agentAState.put("primaryModelRef", JsonString("openai:gpt-4o-mini"))
            agentAState.put("runtimePrimaryModelRef", JsonString("openai:gpt-4o-mini"))
            agentAState.put("providers", JsonArray([]))
            let agentASetParams = JsonObject()
            agentASetParams.put("agentId", JsonString("agent-a"))
            agentASetParams.put("state", agentAState)
            let agentASet = handleGatewayAgentsFamily("agents.models.set", request: Some(GatewayRpcRequest("agents.models.set", params: agentASetParams))).getOrThrow()
            @Expect(agentASet.ok, true)

            let agentBState = JsonObject()
            agentBState.put("primaryModelRef", JsonString("dashscope:qwen-plus"))
            agentBState.put("runtimePrimaryModelRef", JsonString("dashscope:qwen-plus"))
            agentBState.put("providers", JsonArray([]))
            let agentBSetParams = JsonObject()
            agentBSetParams.put("agentId", JsonString("agent-b"))
            agentBSetParams.put("state", agentBState)
            let agentBSet = handleGatewayAgentsFamily("agents.models.set", request: Some(GatewayRpcRequest("agents.models.set", params: agentBSetParams))).getOrThrow()
            @Expect(agentBSet.ok, true)

            let agentAGetParams = JsonObject()
            agentAGetParams.put("agentId", JsonString("agent-a"))
            let agentAGet = handleGatewayAgentsFamily("agents.models.get", request: Some(GatewayRpcRequest("agents.models.get", params: agentAGetParams))).getOrThrow()
            @Expect(agentAGet.ok, true)
            let agentAModels = agentAGet.result.asObject().get("models").getOrThrow().asObject()

            let agentBGetParams = JsonObject()
            agentBGetParams.put("agentId", JsonString("agent-b"))
            let agentBGet = handleGatewayAgentsFamily("agents.models.get", request: Some(GatewayRpcRequest("agents.models.get", params: agentBGetParams))).getOrThrow()
            @Expect(agentBGet.ok, true)
            let agentBModels = agentBGet.result.asObject().get("models").getOrThrow().asObject()

            let agentAPath = home.join("agents").join("agent-a").join("agent").join("models.json")
            let agentBPath = home.join("agents").join("agent-b").join("agent").join("models.json")
            @Expect(agentsTestString(agentAModels, "path"), agentAPath.toString())
            @Expect(agentsTestString(agentBModels, "path"), agentBPath.toString())
            @Expect(agentsTestString(agentAModels, "path") != agentsTestString(agentBModels, "path"), true)
            @Expect(agentsTestString(agentAModels, "modelRef"), "openai:gpt-4o-mini")
            @Expect(agentsTestString(agentBModels, "modelRef"), "dashscope:qwen-plus")
            @Expect(agentsTestString(agentAModels, "runtimePrimaryModelRef"), "openai:gpt-4o-mini")
            @Expect(agentsTestString(agentBModels, "runtimePrimaryModelRef"), "dashscope:qwen-plus")
            @Expect(String.fromUtf8(File.readFrom(agentAPath)).contains("dashscope:qwen-plus"), false)
            @Expect(String.fromUtf8(File.readFrom(agentBPath)).contains("openai:gpt-4o-mini"), false)
        })
    }

    @TestCase
    public func agentBWithoutExplicitAuthCopyDoesNotReadAgentAOrMainCredentialsAndRedactsOutput(): Unit {
        withAgentsTempHome("metis-agents-phase2-auth-isolation-home", { home: Path =>
            File.writeTo(home.join("auth-profiles.json"),
                "{\"profiles\":[{\"id\":\"main-isolated\",\"provider\":\"isolated\",\"apiKey\":\"main-secret-never-log\"}]}\n".toArray())

            let agentAParams = JsonObject()
            agentAParams.put("id", JsonString("agent-a"))
            agentAParams.put("model", JsonString("isolated:agent-a-model"))
            let agentAAdd = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: agentAParams))).getOrThrow()
            @Expect(agentAAdd.ok, true)

            let agentBParams = JsonObject()
            agentBParams.put("id", JsonString("agent-b"))
            agentBParams.put("model", JsonString("isolated:agent-b-model"))
            let agentBAdd = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: agentBParams))).getOrThrow()
            @Expect(agentBAdd.ok, true)

            File.writeTo(
                home.join("agents").join("agent-a").join("agent").join("auth-profiles.json"),
                "{\"profiles\":[{\"id\":\"agent-a-isolated\",\"provider\":\"isolated\",\"apiKey\":\"agent-a-secret-never-log\",\"baseUrl\":\"https://agent-a.example/v1\"}]}\n".toArray()
            )

            let agentAGetParams = JsonObject()
            agentAGetParams.put("agentId", JsonString("agent-a"))
            let agentAGet = handleGatewayAgentsFamily("agents.models.get", request: Some(GatewayRpcRequest("agents.models.get", params: agentAGetParams))).getOrThrow()
            @Expect(agentAGet.ok, true)
            let agentAModels = agentAGet.result.asObject().get("models").getOrThrow().asObject()
            let agentASource = agentsTestObject(agentAModels, "credentialSource")
            @Expect(agentsTestString(agentASource, "source"), "agent.auth-profiles.isolated")
            @Expect(agentsTestString(agentASource, "status"), "configured")
            @Expect(agentsTestBool(agentASource, "apiKeyConfigured"), true)

            let agentBGetParams = JsonObject()
            agentBGetParams.put("agentId", JsonString("agent-b"))
            let agentBGet = handleGatewayAgentsFamily("agents.models.get", request: Some(GatewayRpcRequest("agents.models.get", params: agentBGetParams))).getOrThrow()
            @Expect(agentBGet.ok, true)
            let agentBModels = agentBGet.result.asObject().get("models").getOrThrow().asObject()
            let agentBSource = agentsTestObject(agentBModels, "credentialSource")
            @Expect(agentsTestString(agentBSource, "source"), "unconfigured")
            @Expect(agentsTestString(agentBSource, "status"), "not-configured")
            @Expect(agentsTestBool(agentBSource, "apiKeyConfigured"), false)
            @Expect(agentsTestString(agentBSource, "path"), "")
            @Expect(exists(home.join("agents").join("agent-b").join("agent").join("auth-profiles.json")), false)

            let rendered = agentAModels.toJsonString() + agentBModels.toJsonString()
            @Expect(rendered.contains("agent-a-secret-never-log"), false)
            @Expect(rendered.contains("main-secret-never-log"), false)
            @Expect(rendered.contains("\"apiKey\":\""), false)
            @Expect(rendered.contains("\"api_key\":\""), false)
            @Expect(rendered.contains("Authorization"), false)
        })
    }

    @TestCase
    public func agentModelsRpcReadsWritesAndValidatesAgentDirModelsJson(): Unit {
        withAgentsTempHome("metis-agents-models-phase7-home", { home: Path =>
            let addParams = JsonObject()
            addParams.put("id", JsonString("pm"))
            addParams.put("model", JsonString("qwen:qwen-plus"))
            let addResponse = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: addParams))).getOrThrow()
            @Expect(addResponse.ok, true)

            let statusParams = JsonObject()
            statusParams.put("agentId", JsonString("pm"))
            let statusResponse = handleGatewayAgentsFamily("agents.models.status", request: Some(GatewayRpcRequest("agents.models.status", params: statusParams))).getOrThrow()
            @Expect(statusResponse.ok, true)
            let status = statusResponse.result.asObject().get("models").getOrThrow().asObject()
            let modelsPath = home.join("agents").join("pm").join("agent").join("models.json")
            @Expect(agentsTestString(status, "path"), modelsPath.toString())
            @Expect(agentsTestBool(status, "present"), true)
            @Expect(exists(modelsPath), true)

            let invalidParams = JsonObject()
            invalidParams.put("agentId", JsonString("pm"))
            invalidParams.put("content", JsonString("{bad"))
            let invalid = handleGatewayAgentsFamily("agents.models.set", request: Some(GatewayRpcRequest("agents.models.set", params: invalidParams))).getOrThrow()
            @Expect(invalid.ok, false)

            let nextState = JsonObject()
            nextState.put("primaryModelRef", JsonString("openai:gpt-4o-mini"))
            nextState.put("runtimePrimaryModelRef", JsonString("openai:gpt-4o-mini"))
            nextState.put("providers", JsonArray([]))
            let setParams = JsonObject()
            setParams.put("agentId", JsonString("pm"))
            setParams.put("state", nextState)
            let setResponse = handleGatewayAgentsFamily("agents.models.set", request: Some(GatewayRpcRequest("agents.models.set", params: setParams))).getOrThrow()
            @Expect(setResponse.ok, true)

            let getResponse = handleGatewayAgentsFamily("agents.models.get", request: Some(GatewayRpcRequest("agents.models.get", params: statusParams))).getOrThrow()
            @Expect(getResponse.ok, true)
            let modelState = getResponse.result.asObject().get("models").getOrThrow().asObject().get("state").getOrThrow().asObject()
            @Expect(agentsTestString(modelState, "primaryModelRef"), "openai:gpt-4o-mini")
            @Expect(String.fromUtf8(File.readFrom(modelsPath)).contains("token"), false)
        })
    }

    @TestCase
    public func agentModelsRpcReportsCredentialSourcesWithoutImplicitMainAuthOrSecretLeaks(): Unit {
        withAgentsTempHome("metis-agents-models-source-order-home", { home: Path =>
            File.writeTo(home.join("auth-profiles.json"),
                "{\"profiles\":[{\"id\":\"main-qwen\",\"provider\":\"qwen\",\"apiKey\":\"main-auth-secret\"}]}\n".toArray())

            let addParams = JsonObject()
            addParams.put("id", JsonString("pm"))
            addParams.put("model", JsonString("qwen:qwen-plus"))
            let addResponse = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: addParams))).getOrThrow()
            @Expect(addResponse.ok, true)

            let getParams = JsonObject()
            getParams.put("agentId", JsonString("pm"))
            let missingAuthResponse = handleGatewayAgentsFamily("agents.models.get", request: Some(GatewayRpcRequest("agents.models.get", params: getParams))).getOrThrow()
            @Expect(missingAuthResponse.ok, true)
            let missingModels = missingAuthResponse.result.asObject().get("models").getOrThrow().asObject()
            @Expect(missingModels.get("credentialSource").isSome(), true)
            let missingSource = agentsTestObject(missingModels, "credentialSource")
            let missingRendered = missingModels.toJsonString()
            @Expect(agentsTestString(missingSource, "source"), "unconfigured")
            @Expect(agentsTestString(missingSource, "status"), "not-configured")
            @Expect(missingRendered.contains("main-auth-secret"), false)

            let authPath = home.join("agents").join("pm").join("agent").join("auth-profiles.json")
            File.writeTo(authPath,
                "{\"profiles\":[{\"id\":\"pm-qwen\",\"provider\":\"qwen\",\"apiKey\":\"pm-auth-secret\",\"baseUrl\":\"https://agent.example/v1\"}]}\n".toArray())
            let copiedAuthResponse = handleGatewayAgentsFamily("agents.models.get", request: Some(GatewayRpcRequest("agents.models.get", params: getParams))).getOrThrow()
            @Expect(copiedAuthResponse.ok, true)
            let copiedModels = copiedAuthResponse.result.asObject().get("models").getOrThrow().asObject()
            @Expect(copiedModels.get("credentialSource").isSome(), true)
            let copiedSource = agentsTestObject(copiedModels, "credentialSource")
            let copiedRendered = copiedModels.toJsonString()
            @Expect(agentsTestString(copiedSource, "source"), "agent.auth-profiles.qwen")
            @Expect(agentsTestString(copiedSource, "status"), "configured")
            @Expect(agentsTestBool(copiedSource, "apiKeyConfigured"), true)
            @Expect(copiedRendered.contains("pm-auth-secret"), false)
            @Expect(copiedRendered.contains("main-auth-secret"), false)
        })
    }

    @TestCase
    public func agentRuntimeScopeKeepsPerAgentModelAuthWorkspaceAndSessionPathsSeparate(): Unit {
        withAgentsTempHome("metis-agents-runtime-path-isolation-home", { home: Path =>
            let writerParams = JsonObject()
            writerParams.put("id", JsonString("writer"))
            writerParams.put("model", JsonString("openai:gpt-4o-mini"))
            let writerAdd = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: writerParams))).getOrThrow()
            @Expect(writerAdd.ok, true)

            let opsParams = JsonObject()
            opsParams.put("id", JsonString("ops"))
            opsParams.put("model", JsonString("dashscope:qwen-plus"))
            let opsAdd = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: opsParams))).getOrThrow()
            @Expect(opsAdd.ok, true)

            File.writeTo(
                home.join("agents").join("writer").join("agent").join("auth-profiles.json"),
                "{\"profiles\":[{\"id\":\"writer-openai\",\"provider\":\"openai\",\"apiKey\":\"writer-secret-never-log\"}]}\n".toArray()
            )
            File.writeTo(
                home.join("agents").join("ops").join("agent").join("auth-profiles.json"),
                "{\"profiles\":[{\"id\":\"ops-dashscope\",\"provider\":\"dashscope\",\"apiKey\":\"ops-secret-never-log\"}]}\n".toArray()
            )

            let writerScopeParams = JsonObject()
            writerScopeParams.put("agentId", JsonString("writer"))
            let writerScopeResponse = handleGatewayAgentsFamily("agent.scope", request: Some(GatewayRpcRequest("agent.scope", params: writerScopeParams))).getOrThrow()
            let writerScope = writerScopeResponse.result.asObject().get("scope").getOrThrow().asObject()
            let opsScopeParams = JsonObject()
            opsScopeParams.put("agentId", JsonString("ops"))
            let opsScopeResponse = handleGatewayAgentsFamily("agent.scope", request: Some(GatewayRpcRequest("agent.scope", params: opsScopeParams))).getOrThrow()
            let opsScope = opsScopeResponse.result.asObject().get("scope").getOrThrow().asObject()

            @Expect(agentsTestString(writerScope, "workspaceDir"), home.join("workspaces").join("writer").toString())
            @Expect(agentsTestString(opsScope, "workspaceDir"), home.join("workspaces").join("ops").toString())
            @Expect(agentsTestString(writerScope, "agentDir"), home.join("agents").join("writer").join("agent").toString())
            @Expect(agentsTestString(opsScope, "agentDir"), home.join("agents").join("ops").join("agent").toString())
            @Expect(agentsTestString(writerScope, "modelsJsonPath") != agentsTestString(opsScope, "modelsJsonPath"), true)
            @Expect(agentsTestString(writerScope, "authProfilesPath") != agentsTestString(opsScope, "authProfilesPath"), true)
            @Expect(agentsTestString(writerScope, "sessionsDir") != agentsTestString(opsScope, "sessionsDir"), true)
            @Expect(agentsTestString(writerScope, "modelRef"), "openai:gpt-4o-mini")
            @Expect(agentsTestString(opsScope, "modelRef"), "dashscope:qwen-plus")

            let writerModelsResponse = handleGatewayAgentsFamily("agents.models.get", request: Some(GatewayRpcRequest("agents.models.get", params: writerScopeParams))).getOrThrow()
            let writerModels = writerModelsResponse.result.asObject().get("models").getOrThrow().asObject()
            let opsModelsResponse = handleGatewayAgentsFamily("agents.models.get", request: Some(GatewayRpcRequest("agents.models.get", params: opsScopeParams))).getOrThrow()
            let opsModels = opsModelsResponse.result.asObject().get("models").getOrThrow().asObject()
            let writerSource = agentsTestObject(writerModels, "credentialSource")
            let opsSource = agentsTestObject(opsModels, "credentialSource")

            @Expect(agentsTestString(writerSource, "source"), "agent.auth-profiles.openai")
            @Expect(agentsTestString(opsSource, "source"), "agent.auth-profiles.dashscope")
            let rendered = writerModels.toJsonString() + opsModels.toJsonString()
            @Expect(rendered.contains("writer-secret-never-log"), false)
            @Expect(rendered.contains("ops-secret-never-log"), false)
            @Expect(rendered.contains("agent.auth-profiles.openai"), true)
            @Expect(rendered.contains("agent.auth-profiles.dashscope"), true)
        })
    }

    @TestCase
    public func agentUpdateRefreshesGeneratedModelsJsonButPreservesManualState(): Unit {
        withAgentsTempHome("metis-agents-models-refresh-hook-home", { home: Path =>
            let addParams = JsonObject()
            addParams.put("id", JsonString("pm"))
            addParams.put("model", JsonString("qwen:qwen-plus"))
            let addResponse = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: addParams))).getOrThrow()
            @Expect(addResponse.ok, true)

            let statusParams = JsonObject()
            statusParams.put("agentId", JsonString("pm"))
            let statusResponse = handleGatewayAgentsFamily("agents.models.status", request: Some(GatewayRpcRequest("agents.models.status", params: statusParams))).getOrThrow()
            @Expect(statusResponse.ok, true)
            let modelsPath = home.join("agents").join("pm").join("agent").join("models.json")
            let initialState = statusResponse.result.asObject().get("models").getOrThrow().asObject().get("state").getOrThrow().asObject()
            @Expect(agentsTestString(initialState, "runtimePrimaryModelRef").contains("qwen-plus"), true)
            @Expect(agentsTestBool(initialState, "generated"), true)

            let updateParams = JsonObject()
            updateParams.put("id", JsonString("pm"))
            updateParams.put("model", JsonString("openai:gpt-4o-mini"))
            let updateResponse = handleGatewayAgentsFamily("agents.update", request: Some(GatewayRpcRequest("agents.update", params: updateParams))).getOrThrow()
            @Expect(updateResponse.ok, true)
            let refresh = updateResponse.result.asObject().get("modelsRefresh").getOrThrow().asObject()
            @Expect(agentsTestString(refresh, "status"), "refreshed")
            @Expect(agentsTestBool(refresh, "refreshed"), true)
            let generatedGet = handleGatewayAgentsFamily("agents.models.get", request: Some(GatewayRpcRequest("agents.models.get", params: statusParams))).getOrThrow()
            let generatedState = generatedGet.result.asObject().get("models").getOrThrow().asObject().get("state").getOrThrow().asObject()
            @Expect(agentsTestString(generatedState, "runtimePrimaryModelRef"), "openai:gpt-4o-mini")

            let manualState = JsonObject()
            manualState.put("primaryModelRef", JsonString("manual:model"))
            manualState.put("runtimePrimaryModelRef", JsonString("manual:model"))
            manualState.put("providers", JsonArray([]))
            let setParams = JsonObject()
            setParams.put("agentId", JsonString("pm"))
            setParams.put("state", manualState)
            let setResponse = handleGatewayAgentsFamily("agents.models.set", request: Some(GatewayRpcRequest("agents.models.set", params: setParams))).getOrThrow()
            @Expect(setResponse.ok, true)

            let manualUpdateParams = JsonObject()
            manualUpdateParams.put("id", JsonString("pm"))
            manualUpdateParams.put("model", JsonString("anthropic:claude-3-5-sonnet"))
            let manualUpdate = handleGatewayAgentsFamily("agents.update", request: Some(GatewayRpcRequest("agents.update", params: manualUpdateParams))).getOrThrow()
            @Expect(manualUpdate.ok, true)
            let manualRefresh = manualUpdate.result.asObject().get("modelsRefresh").getOrThrow().asObject()
            @Expect(agentsTestString(manualRefresh, "status"), "skipped")
            @Expect(agentsTestString(manualRefresh, "reason"), "manual-runtime-state")
            @Expect(agentsTestBool(manualRefresh, "refreshed"), false)
            let manualContent = String.fromUtf8(File.readFrom(modelsPath))
            @Expect(manualContent.contains("manual:model"), true)
            @Expect(manualContent.contains("anthropic:claude-3-5-sonnet"), false)
        })
    }

    @TestCase
    public func agentTeamsCreateUpdateCompileBindingsAndDeletePreservesRoutes(): Unit {
        withAgentsTempHome("metis-agent-teams-bindings-compile-home", { _home: Path =>
            let createBindings = JsonArray([])
            createBindings.add(agentsTestRouteBinding("content-writer", "telegram", accountId: "bot-a", peerKind: "group", peerId: "-100_content"))
            let createParams = JsonObject()
            createParams.put("id", JsonString("content"))
            createParams.put("template", JsonString("pm-writer-reviewer"))
            createParams.put("bindings", createBindings)
            let createResponse = handleGatewayAgentsFamily("agents.teams.create", request: Some(GatewayRpcRequest("agents.teams.create", params: createParams))).getOrThrow()
            @Expect(createResponse.ok, true)
            let createResult = createResponse.result.asObject()
            @Expect(createResult.get("bindingApply").getOrThrow().asObject().get("added").getOrThrow().asArray().size(), 1)

            let telegramRoute = gatewayResolveAgentRoute(GatewayAgentRouteInput(
                MetisConfigManager.rawConfig().getOrThrow(),
                "telegram",
                accountId: "bot-a",
                peerKind: "group",
                peerId: "-100_content"
            ))
            @Expect(telegramRoute.agentId, "content-writer")
            @Expect(telegramRoute.matchedBy, "binding.peer.exact")

            let updateBindings = JsonArray([])
            updateBindings.add(agentsTestRouteBinding("content-reviewer", "feishu", accountId: "tenant-a", peerKind: "thread", peerId: "thread-review"))
            let updateParams = JsonObject()
            updateParams.put("id", JsonString("content"))
            updateParams.put("bindings", updateBindings)
            let updateResponse = handleGatewayAgentsFamily("agents.teams.update", request: Some(GatewayRpcRequest("agents.teams.update", params: updateParams))).getOrThrow()
            @Expect(updateResponse.ok, true)
            @Expect(updateResponse.result.asObject().get("bindingApply").getOrThrow().asObject().get("added").getOrThrow().asArray().size(), 1)

            let rootAfterUpdate = MetisConfigManager.rawConfig().getOrThrow()
            let telegramAfterUpdate = gatewayResolveAgentRoute(GatewayAgentRouteInput(
                rootAfterUpdate,
                "telegram",
                accountId: "bot-a",
                peerKind: "group",
                peerId: "-100_content"
            ))
            let feishuAfterUpdate = gatewayResolveAgentRoute(GatewayAgentRouteInput(
                rootAfterUpdate,
                "feishu",
                accountId: "tenant-a",
                peerKind: "thread",
                peerId: "thread-review"
            ))
            @Expect(telegramAfterUpdate.agentId, "content-writer")
            @Expect(feishuAfterUpdate.agentId, "content-reviewer")

            let deleteParams = JsonObject()
            deleteParams.put("id", JsonString("content"))
            let deleteResponse = handleGatewayAgentsFamily("agents.teams.delete", request: Some(GatewayRpcRequest("agents.teams.delete", params: deleteParams))).getOrThrow()
            @Expect(deleteResponse.ok, true)
            let rootAfterDelete = MetisConfigManager.rawConfig().getOrThrow()
            @Expect(gatewayResolveAgentRoute(GatewayAgentRouteInput(
                rootAfterDelete,
                "telegram",
                accountId: "bot-a",
                peerKind: "group",
                peerId: "-100_content"
            )).agentId, "content-writer")
            @Expect(gatewayResolveAgentRoute(GatewayAgentRouteInput(
                rootAfterDelete,
                "feishu",
                accountId: "tenant-a",
                peerKind: "thread",
                peerId: "thread-review"
            )).agentId, "content-reviewer")
        })
    }

    @TestCase
    public func agentTeamFakeImE2eCoversTelegramFeishuRoutesAndBroadcast(): Unit {
        withAgentsTempHome("metis-agent-team-fake-im-e2e-home", { _home: Path =>
            let bindings = JsonArray([])
            bindings.add(agentsTestRouteBinding("e2e-writer", "telegram", accountId: "bot-a", peerKind: "group", peerId: "-100_e2e"))
            bindings.add(agentsTestRouteBinding("e2e-reviewer", "feishu", accountId: "tenant-a", peerKind: "thread", peerId: "thread-e2e"))

            let broadcast = JsonObject()
            broadcast.put("enabled", JsonBool(true))
            broadcast.put("members", agentsTestStringArray(["e2e-writer", "e2e-reviewer"]))

            let createParams = JsonObject()
            createParams.put("id", JsonString("e2e"))
            createParams.put("displayName", JsonString("Fake IM E2E Team"))
            createParams.put("template", JsonString("pm-writer-reviewer"))
            createParams.put("bindings", bindings)
            createParams.put("broadcast", broadcast)
            let createResponse = handleGatewayAgentsFamily("agents.teams.create", request: Some(GatewayRpcRequest("agents.teams.create", params: createParams))).getOrThrow()
            @Expect(createResponse.ok, true)
            @Expect(createResponse.result.asObject().get("bindingApply").getOrThrow().asObject().get("added").getOrThrow().asArray().size(), 2)

            let root = MetisConfigManager.rawConfig().getOrThrow()
            let telegramRoute = gatewayResolveAgentRoute(GatewayAgentRouteInput(
                root,
                "telegram",
                accountId: "bot-a",
                peerKind: "group",
                peerId: "-100_e2e"
            ))
            @Expect(telegramRoute.agentId, "e2e-writer")
            @Expect(telegramRoute.matchedBy, "binding.peer.exact")
            @Expect(telegramRoute.sessionKey, "agent:e2e-writer:telegram:group:-100_e2e")

            let feishuRoute = gatewayResolveAgentRoute(GatewayAgentRouteInput(
                root,
                "feishu",
                accountId: "tenant-a",
                peerKind: "thread",
                peerId: "thread-e2e",
                parentPeerKind: "group",
                parentPeerId: "chat-e2e"
            ))
            @Expect(feishuRoute.agentId, "e2e-reviewer")
            @Expect(feishuRoute.matchedBy, "binding.peer.exact")
            @Expect(feishuRoute.sessionKey, "agent:e2e-reviewer:feishu:thread:thread-e2e")

            let broadcastPlan = gatewayResolveAgentTeamBroadcastPlan(GatewaySessionRequest(
                GatewayIngressSource.Channel("telegram"),
                channelName: "telegram",
                text: "fake team acceptance",
                accountId: "bot-a",
                peerId: "-100_e2e",
                senderId: "sender-e2e",
                routeRoot: root,
                routeAccountId: "bot-a",
                routePeerKind: "group",
                routePeerId: "-100_e2e"
            ))
            @Expect(broadcastPlan.enabled, true)
            @Expect(broadcastPlan.teamId, "e2e")
            @Expect(broadcastPlan.turns.size, 2)
            @Expect(broadcastPlan.turns[0].agentId, "e2e-writer")
            @Expect(broadcastPlan.turns[0].context.sessionKey, "agent:e2e-writer:telegram:group:-100_e2e")
            @Expect(broadcastPlan.turns[1].agentId, "e2e-reviewer")
            @Expect(broadcastPlan.turns[1].context.sessionKey, "agent:e2e-reviewer:telegram:group:-100_e2e")

            let getParams = JsonObject()
            getParams.put("id", JsonString("e2e"))
            let getResponse = handleGatewayAgentsFamily("agents.teams.get", request: Some(GatewayRpcRequest("agents.teams.get", params: getParams))).getOrThrow()
            @Expect(getResponse.ok, true)
            let persistedBroadcast = getResponse.result.asObject().get("team").getOrThrow().asObject().get("broadcast").getOrThrow().asObject()
            @Expect(agentsTestBool(persistedBroadcast, "enabled"), true)
            @Expect(persistedBroadcast.get("members").getOrThrow().asArray().size(), 2)
        })
    }

    @TestCase
    public func agentTeamRpcResponsesExposeProductSemanticsWithoutManagerRuntimePromise(): Unit {
        withAgentsTempHome("metis-agent-team-product-semantics-home", { _home: Path =>
            let createParams = JsonObject()
            createParams.put("id", JsonString("content"))
            createParams.put("template", JsonString("pm-writer-reviewer"))
            createParams.put("defaultAgentId", JsonString("content-pm"))
            let createResponse = handleGatewayAgentsFamily("agents.teams.create", request: Some(GatewayRpcRequest("agents.teams.create", params: createParams))).getOrThrow()
            @Expect(createResponse.ok, true)
            let createResult = createResponse.result.asObject()
            let semantics = agentsTestObject(createResult, "semantics")
            @Expect(agentsTestString(semantics, "singleRoute"), "deterministic-single-agent")
            @Expect(agentsTestString(semantics, "broadcast"), "explicit-fan-out")
            @Expect(agentsTestString(semantics, "manager"), "member-or-default-agent-only")
            @Expect(agentsTestBool(semantics, "autonomousManagerRuntime"), false)
            @Expect(agentsTestString(semantics, "crudSurface"), "cli-ui-gateway-rpc")
            @Expect(agentsTestString(semantics, "imSurface"), "runtime-route-alias-native-command")
            @Expect(agentsTestString(semantics, "nativeCommandSurface"), "runtime-route-native-command-only")
            @Expect(agentsTestBool(semantics, "deletePreservesMemberAgents"), true)
            let crudMethods = semantics.get("crudMethods").getOrThrow().asArray()
            @Expect(agentsTestArrayContains(crudMethods, "list"), true)
            @Expect(agentsTestArrayContains(crudMethods, "get"), true)
            @Expect(agentsTestArrayContains(crudMethods, "create"), true)
            @Expect(agentsTestArrayContains(crudMethods, "update"), true)
            @Expect(agentsTestArrayContains(crudMethods, "delete"), true)

            let getParams = JsonObject()
            getParams.put("id", JsonString("content"))
            let getResponse = handleGatewayAgentsFamily("agents.teams.get", request: Some(GatewayRpcRequest("agents.teams.get", params: getParams))).getOrThrow()
            @Expect(getResponse.ok, true)
            @Expect(agentsTestString(agentsTestObject(getResponse.result.asObject(), "semantics"), "manager"), "member-or-default-agent-only")
        })
    }

    @TestCase
    public func agentTeamBroadcastAggregateCoversPartialAndAllFailureWithPerMemberFields(): Unit {
        withAgentsTempHome("metis-agent-team-broadcast-aggregate-failures-home", { _home: Path =>
            let bindings = JsonArray([])
            bindings.add(agentsTestRouteBinding("content-pm", "telegram", accountId: "bot-a", peerKind: "group", peerId: "-100_content"))
            let broadcast = JsonObject()
            broadcast.put("enabled", JsonBool(true))
            broadcast.put("members", agentsTestStringArray(["content-pm", "content-writer", "content-reviewer"]))
            let createParams = JsonObject()
            createParams.put("id", JsonString("content"))
            createParams.put("template", JsonString("pm-writer-reviewer"))
            createParams.put("bindings", bindings)
            createParams.put("broadcast", broadcast)
            @Expect(handleGatewayAgentsFamily("agents.teams.create", request: Some(GatewayRpcRequest("agents.teams.create", params: createParams))).getOrThrow().ok, true)

            let root = MetisConfigManager.rawConfig().getOrThrow()
            let plan = gatewayResolveAgentTeamBroadcastPlan(GatewaySessionRequest(
                GatewayIngressSource.Channel("telegram"),
                channelName: "telegram",
                text: "team fan-out",
                accountId: "bot-a",
                peerId: "-100_content",
                senderId: "sender-content",
                routeRoot: root,
                routeAccountId: "bot-a",
                routePeerKind: "group",
                routePeerId: "-100_content"
            ))
            @Expect(plan.enabled, true)
            @Expect(plan.turns.size, 3)

            let delivered = GatewayResolvedSessionTurnResult(
                plan.turns[0].context,
                GatewaySessionExecutionResult("pm answer", delivered: true, deliveryStatus: "delivered", deliveryMessageId: "m-pm")
            )
            let failed = GatewayResolvedSessionTurnResult(
                plan.turns[1].context,
                GatewaySessionExecutionResult("", delivered: false, deliveryStatus: "send-failed", deliveryError: "synthetic send failure")
            )
            let partial = gatewayAgentTeamBroadcastAggregateJson(plan, [failed, delivered])
            @Expect(agentsTestString(partial, "status"), "partial")
            @Expect(partial.get("deliveredCount").getOrThrow().asInt().getValue(), 1)
            let partialAgents = partial.get("agents").getOrThrow().asArray()
            @Expect(agentsTestString(partialAgents[0].asObject(), "agentId"), "content-pm")
            @Expect(agentsTestString(partialAgents[0].asObject(), "status"), "delivered")
            @Expect(partialAgents[0].asObject().get("elapsedMs").isSome(), true)
            @Expect(agentsTestString(partialAgents[0].asObject(), "detail"), "delivered")
            @Expect(agentsTestString(partialAgents[1].asObject(), "error"), "synthetic send failure")
            @Expect(partialAgents[1].asObject().get("elapsedMs").isSome(), true)
            @Expect(agentsTestString(partialAgents[1].asObject(), "detail"), "send-failed: synthetic send failure")
            @Expect(agentsTestString(partialAgents[2].asObject(), "status"), "missing-result")
            @Expect(partialAgents[2].asObject().get("elapsedMs").isSome(), true)
            @Expect(agentsTestString(partialAgents[2].asObject(), "detail"), "missing-result: no execution result for broadcast member")

            let allFailed = gatewayAgentTeamBroadcastAggregateJson(plan, [failed])
            @Expect(agentsTestString(allFailed, "status"), "failed")
            @Expect(allFailed.get("deliveredCount").getOrThrow().asInt().getValue(), 0)
            let failedAgents = allFailed.get("agents").getOrThrow().asArray()
            @Expect(agentsTestString(failedAgents[1].asObject(), "error"), "synthetic send failure")
            @Expect(agentsTestString(failedAgents[1].asObject(), "detail"), "send-failed: synthetic send failure")
        })
    }

    @TestCase
    public func agentTeamAliasMentionsPmWriterReviewerOverrideRouteBinding(): Unit {
        withAgentsTempHome("metis-agent-team-alias-priority-home", { _home: Path =>
            let bindings = JsonArray([])
            bindings.add(agentsTestRouteBinding("content-pm", "telegram", accountId: "bot-a", peerKind: "group", peerId: "-100_content"))
            let aliases = JsonArray([])
            aliases.add(agentsTestTeamAlias("@pm", "content-pm"))
            aliases.add(agentsTestTeamAlias("@writer", "content-writer"))
            aliases.add(agentsTestTeamAlias("@reviewer", "content-reviewer"))
            let createParams = JsonObject()
            createParams.put("id", JsonString("content"))
            createParams.put("template", JsonString("pm-writer-reviewer"))
            createParams.put("bindings", bindings)
            createParams.put("aliases", aliases)
            @Expect(handleGatewayAgentsFamily("agents.teams.create", request: Some(GatewayRpcRequest("agents.teams.create", params: createParams))).getOrThrow().ok, true)

            let root = MetisConfigManager.rawConfig().getOrThrow()
            let pm = gatewayResolveSessionContextWithAgentRoute(GatewaySessionRequest(
                GatewayIngressSource.Channel("telegram"),
                channelName: "telegram",
                text: "@pm triage this",
                accountId: "bot-a",
                peerId: "-100_content",
                senderId: "sender-content",
                routeRoot: root,
                routeAccountId: "bot-a",
                routePeerKind: "group",
                routePeerId: "-100_content"
            ))
            let writer = gatewayResolveSessionContextWithAgentRoute(GatewaySessionRequest(
                GatewayIngressSource.Channel("telegram"),
                channelName: "telegram",
                text: "@writer draft this",
                accountId: "bot-a",
                peerId: "-100_content",
                senderId: "sender-content",
                routeRoot: root,
                routeAccountId: "bot-a",
                routePeerKind: "group",
                routePeerId: "-100_content"
            ))
            let reviewer = gatewayResolveSessionContextWithAgentRoute(GatewaySessionRequest(
                GatewayIngressSource.Channel("telegram"),
                channelName: "telegram",
                text: "@reviewer check this",
                accountId: "bot-a",
                peerId: "-100_content",
                senderId: "sender-content",
                routeRoot: root,
                routeAccountId: "bot-a",
                routePeerKind: "group",
                routePeerId: "-100_content"
            ))

            @Expect(pm.agentId, "content-pm")
            @Expect(pm.matchedBy, "alias.mention")
            @Expect(writer.agentId, "content-writer")
            @Expect(writer.matchedBy, "alias.mention")
            @Expect(reviewer.agentId, "content-reviewer")
            @Expect(reviewer.matchedBy, "alias.mention")
        })
    }

    @TestCase
    public func agentTeamMigrationDryRunRpcReportsPreviewWithoutWritingConfig(): Unit {
        withAgentsTempHome("metis-agent-team-migration-rpc-home", { home: Path =>
            @Expect(agentsTestAddAgent("main").ok, false)
            @Expect(agentsTestAddAgent("ops").ok, true)
            let before = MetisConfigManager.rawConfig().getOrThrow().toJsonString()

            let oldRoot = JsonObject()
            let agents = JsonObject()
            let list = JsonArray([])
            let mainAgent = JsonObject()
            mainAgent.put("id", JsonString("main"))
            mainAgent.put("workspace", JsonString(home.join("legacy-main-workspace").toString()))
            mainAgent.put("default", JsonBool(true))
            list.add(mainAgent)
            let reviewer = JsonObject()
            reviewer.put("id", JsonString("reviewer"))
            reviewer.put("workspace", JsonString(home.join("legacy-reviewer-workspace").toString()))
            list.add(reviewer)
            agents.put("list", list)
            oldRoot.put("agents", agents)

            let proposed = JsonArray([])
            proposed.add(agentsTestRouteBinding("reviewer", "telegram", accountId: "bot-a"))
            let params = JsonObject()
            params.put("configRoot", oldRoot)
            params.put("proposedBindings", proposed)
            params.put("homeRoot", JsonString(home.toString()))
            params.put("defaultWorkspace", JsonString(home.join("workspace").toString()))

            let response = handleGatewayAgentsFamily("agents.migration.dryRun",
                request: Some(GatewayRpcRequest("agents.migration.dryRun", params: params))).getOrThrow()
            @Expect(response.ok, true)
            let result = response.result.asObject()
            @Expect(agentsTestString(result, "kind"), "agent-team-migration")
            @Expect(agentsTestString(result, "mode"), "dry-run")
            @Expect(agentsTestBool(result, "readOnly"), true)
            let bindingApply = agentsTestObject(result, "bindingApply")
            @Expect(bindingApply.get("added").getOrThrow().asArray().size(), 1)
            @Expect(MetisConfigManager.rawConfig().getOrThrow().toJsonString(), before)
        })
    }

    @TestCase
    public func agentTeamsCreateBindingConflictDoesNotWritePartialConfig(): Unit {
        withAgentsTempHome("metis-agent-teams-create-conflict-home", { home: Path =>
            @Expect(agentsTestAddAgent("ops").ok, true)
            let bindParams = JsonObject()
            bindParams.put("agentId", JsonString("ops"))
            bindParams.put("bind", JsonString("telegram:bot-a"))
            let bindResponse = handleGatewayAgentsFamily("agents.bind", request: Some(GatewayRpcRequest("agents.bind", params: bindParams))).getOrThrow()
            @Expect(bindResponse.ok, true)

            let teamBindings = JsonArray([])
            teamBindings.add(agentsTestRouteBinding("content-writer", "telegram", accountId: "bot-a"))
            let createParams = JsonObject()
            createParams.put("id", JsonString("content"))
            createParams.put("template", JsonString("pm-writer-reviewer"))
            createParams.put("bindings", teamBindings)
            let createResponse = handleGatewayAgentsFamily("agents.teams.create", request: Some(GatewayRpcRequest("agents.teams.create", params: createParams))).getOrThrow()
            @Expect(createResponse.ok, false)
            @Expect(createResponse.error.contains("conflict"), true)

            let listResponse = handleGatewayAgentsFamily("agents.teams.list").getOrThrow()
            @Expect(listResponse.result.asObject().get("teams").getOrThrow().asArray().size(), 0)
            let persisted = MetisConfigManager.rawConfig().getOrThrow()
            @Expect(gatewayResolveAgentRoute(GatewayAgentRouteInput(persisted, "telegram", accountId: "bot-a")).agentId, "ops")
            @Expect(persisted.toJsonString().contains("content-writer"), false)
            @Expect(exists(home.join("agents").join("content-writer")), false)
        })
    }

    @TestCase
    public func agentTeamsUpdateBindingConflictDoesNotPersistDraftBindings(): Unit {
        withAgentsTempHome("metis-agent-teams-update-conflict-home", { _home: Path =>
            let createParams = JsonObject()
            createParams.put("id", JsonString("content"))
            createParams.put("template", JsonString("pm-writer-reviewer"))
            let createResponse = handleGatewayAgentsFamily("agents.teams.create", request: Some(GatewayRpcRequest("agents.teams.create", params: createParams))).getOrThrow()
            @Expect(createResponse.ok, true)
            @Expect(agentsTestAddAgent("ops").ok, true)

            let bindParams = JsonObject()
            bindParams.put("agentId", JsonString("ops"))
            bindParams.put("bind", JsonString("telegram:bot-a"))
            let bindResponse = handleGatewayAgentsFamily("agents.bind", request: Some(GatewayRpcRequest("agents.bind", params: bindParams))).getOrThrow()
            @Expect(bindResponse.ok, true)

            let updateBindings = JsonArray([])
            updateBindings.add(agentsTestRouteBinding("content-writer", "telegram", accountId: "bot-a"))
            let updateParams = JsonObject()
            updateParams.put("id", JsonString("content"))
            updateParams.put("bindings", updateBindings)
            let updateResponse = handleGatewayAgentsFamily("agents.teams.update", request: Some(GatewayRpcRequest("agents.teams.update", params: updateParams))).getOrThrow()
            @Expect(updateResponse.ok, false)
            @Expect(updateResponse.error.contains("conflict"), true)

            let getParams = JsonObject()
            getParams.put("id", JsonString("content"))
            let getResponse = handleGatewayAgentsFamily("agents.teams.get", request: Some(GatewayRpcRequest("agents.teams.get", params: getParams))).getOrThrow()
            @Expect(getResponse.ok, true)
            let team = getResponse.result.asObject().get("team").getOrThrow().asObject()
            @Expect(team.get("bindings").getOrThrow().asArray().size(), 0)
            @Expect(agentsTestRawBindings().toJsonString().contains("\"agentId\":\"content-writer\""), false)
        })
    }

    @TestCase
    public func agentTeamsCreateRejectsDuplicateAgentDirWithoutPartialConfig(): Unit {
        withAgentsTempHome("metis-agent-teams-create-duplicate-agentdir-home", { home: Path =>
            @Expect(agentsTestAddAgent("ops").ok, true)
            let root = MetisConfigManager.rawConfig().getOrThrow()
            let agents = agentsTestObject(root, "agents")
            let list = match (agents.get("list")) {
                case Some(v) => try { v.asArray() } catch (_: Exception) { JsonArray([]) }
                case None => JsonArray([])
            }
            let legacy = JsonObject()
            legacy.put("id", JsonString("legacy"))
            legacy.put("workspace", JsonString(home.join("workspaces").join("legacy").toString()))
            legacy.put("agentDir", JsonString(home.join("agents").join("content-pm").join("agent").toString()))
            legacy.put("sessionsDir", JsonString(home.join("agents").join("legacy").join("sessions").toString()))
            list.add(legacy)
            agents.put("list", list)
            root.put("agents", agents)
            MetisConfigManager.writeRoot(root)
            let before = MetisConfigManager.rawConfig().getOrThrow().toJsonString()

            let createParams = JsonObject()
            createParams.put("id", JsonString("content"))
            createParams.put("template", JsonString("pm-writer-reviewer"))
            let create = handleGatewayAgentsFamily("agents.teams.create", request: Some(GatewayRpcRequest("agents.teams.create", params: createParams))).getOrThrow()

            @Expect(create.ok, false)
            @Expect(create.error.contains("Duplicate agentDir"), true)
            @Expect(MetisConfigManager.rawConfig().getOrThrow().toJsonString(), before)
            let listResponse = handleGatewayAgentsFamily("agents.teams.list").getOrThrow()
            @Expect(listResponse.result.asObject().get("teams").getOrThrow().asArray().size(), 0)
            @Expect(exists(home.join("agents").join("content-pm").join("agent").join("AGENT.md")), false)
            @Expect(exists(home.join("workspaces").join("content-writer")), false)
        })
    }

    @TestCase
    public func agentTeamsUpdateRejectsDuplicateAgentDirWithoutPartialConfig(): Unit {
        withAgentsTempHome("metis-agent-teams-update-duplicate-agentdir-home", { home: Path =>
            let members = JsonArray([])
            members.add(agentsTestTeamMember("content-pm", role: "pm", name: "Content PM"))
            let createParams = JsonObject()
            createParams.put("id", JsonString("content"))
            createParams.put("members", members)
            let create = handleGatewayAgentsFamily("agents.teams.create", request: Some(GatewayRpcRequest("agents.teams.create", params: createParams))).getOrThrow()
            @Expect(create.ok, true)

            let root = MetisConfigManager.rawConfig().getOrThrow()
            let agents = agentsTestObject(root, "agents")
            let list = match (agents.get("list")) {
                case Some(v) => try { v.asArray() } catch (_: Exception) { JsonArray([]) }
                case None => JsonArray([])
            }
            let legacy = JsonObject()
            legacy.put("id", JsonString("legacy"))
            legacy.put("workspace", JsonString(home.join("workspaces").join("legacy").toString()))
            legacy.put("agentDir", JsonString(home.join("agents").join("content-reviewer").join("agent").toString()))
            legacy.put("sessionsDir", JsonString(home.join("agents").join("legacy").join("sessions").toString()))
            list.add(legacy)
            agents.put("list", list)
            root.put("agents", agents)
            MetisConfigManager.writeRoot(root)
            let before = MetisConfigManager.rawConfig().getOrThrow().toJsonString()

            let nextMembers = JsonArray([])
            nextMembers.add(agentsTestTeamMember("content-pm", role: "pm", name: "Content PM"))
            nextMembers.add(agentsTestTeamMember("content-reviewer", role: "reviewer", name: "Content Reviewer"))
            let updateParams = JsonObject()
            updateParams.put("id", JsonString("content"))
            updateParams.put("members", nextMembers)
            let update = handleGatewayAgentsFamily("agents.teams.update", request: Some(GatewayRpcRequest("agents.teams.update", params: updateParams))).getOrThrow()

            @Expect(update.ok, false)
            @Expect(update.error.contains("Duplicate agentDir"), true)
            @Expect(MetisConfigManager.rawConfig().getOrThrow().toJsonString(), before)
            let getParams = JsonObject()
            getParams.put("id", JsonString("content"))
            let get = handleGatewayAgentsFamily("agents.teams.get", request: Some(GatewayRpcRequest("agents.teams.get", params: getParams))).getOrThrow()
            let persistedMembers = get.result.asObject().get("team").getOrThrow().asObject().get("members").getOrThrow().asArray()
            @Expect(persistedMembers.size(), 1)
            @Expect(exists(home.join("agents").join("content-reviewer").join("agent").join("AGENT.md")), false)
        })
    }

    @TestCase
    public func teamCreateIsolationAcceptanceUsesTempHomeAndDeleteKeepsUserWorkspace(): Unit {
        withAgentsTempHome("metis-agent-team-phase2-isolation-acceptance-home", { home: Path =>
            let userWorkspace = home.join("user-writer-workspace")
            Directory.create(userWorkspace, recursive: true)
            File.writeTo(userWorkspace.join("USER.md"), "user-owned-workspace\n".toArray())

            let writerParams = JsonObject()
            writerParams.put("id", JsonString("user-writer"))
            writerParams.put("workspace", JsonString(userWorkspace.toString()))
            writerParams.put("model", JsonString("openai:writer-model"))
            let writerAdd = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: writerParams))).getOrThrow()
            @Expect(writerAdd.ok, true)

            let members = JsonArray([])
            members.add(agentsTestTeamMember("user-writer", role: "writer", name: "User Writer"))
            members.add(agentsTestTeamMember("team-reviewer", role: "reviewer", name: "Team Reviewer"))
            let createParams = JsonObject()
            createParams.put("id", JsonString("phase2"))
            createParams.put("members", members)
            let createResponse = handleGatewayAgentsFamily("agents.teams.create", request: Some(GatewayRpcRequest("agents.teams.create", params: createParams))).getOrThrow()
            @Expect(createResponse.ok, true)
            let createdAgents = createResponse.result.asObject().get("agents").getOrThrow().asArray()
            let writerRow = agentsTestFindObjectById(createdAgents, "user-writer")
            let reviewerRow = agentsTestFindObjectById(createdAgents, "team-reviewer")
            @Expect(agentsTestString(writerRow, "workspace"), userWorkspace.toString())
            @Expect(agentsTestString(reviewerRow, "workspace"), home.join("workspaces").join("team-reviewer").toString())
            @Expect(agentsTestString(writerRow, "agentDir") != agentsTestString(reviewerRow, "agentDir"), true)
            @Expect(agentsTestString(writerRow, "sessionsDir") != agentsTestString(reviewerRow, "sessionsDir"), true)
            @Expect(exists(home.join("agents").join("team-reviewer").join("agent").join("AGENT.md")), true)
            @Expect(exists(home.join("agents").join("team-reviewer").join("agent").join("auth-profiles.json")), false)

            let writerSoul = JsonObject()
            writerSoul.put("agentId", JsonString("user-writer"))
            writerSoul.put("name", JsonString("SOUL.md"))
            writerSoul.put("content", JsonString("writer-only-soul\n"))
            @Expect(handleGatewayAgentsFamily("agents.files.set", request: Some(GatewayRpcRequest("agents.files.set", params: writerSoul))).getOrThrow().ok, true)

            let reviewerSoul = JsonObject()
            reviewerSoul.put("agentId", JsonString("team-reviewer"))
            reviewerSoul.put("name", JsonString("SOUL.md"))
            reviewerSoul.put("content", JsonString("reviewer-only-soul\n"))
            @Expect(handleGatewayAgentsFamily("agents.files.set", request: Some(GatewayRpcRequest("agents.files.set", params: reviewerSoul))).getOrThrow().ok, true)
            @Expect(String.fromUtf8(File.readFrom(userWorkspace.join("SOUL.md"))).contains("writer-only-soul"), true)
            @Expect(String.fromUtf8(File.readFrom(home.join("workspaces").join("team-reviewer").join("SOUL.md"))).contains("reviewer-only-soul"), true)
            @Expect(String.fromUtf8(File.readFrom(home.join("workspaces").join("team-reviewer").join("SOUL.md"))).contains("writer-only-soul"), false)

            let writerState = JsonObject()
            writerState.put("primaryModelRef", JsonString("openai:writer-model"))
            writerState.put("runtimePrimaryModelRef", JsonString("openai:writer-model"))
            writerState.put("providers", JsonArray([]))
            let writerModelSetParams = JsonObject()
            writerModelSetParams.put("agentId", JsonString("user-writer"))
            writerModelSetParams.put("state", writerState)
            @Expect(handleGatewayAgentsFamily("agents.models.set", request: Some(GatewayRpcRequest("agents.models.set", params: writerModelSetParams))).getOrThrow().ok, true)

            let reviewerState = JsonObject()
            reviewerState.put("primaryModelRef", JsonString("dashscope:reviewer-model"))
            reviewerState.put("runtimePrimaryModelRef", JsonString("dashscope:reviewer-model"))
            reviewerState.put("providers", JsonArray([]))
            let reviewerModelSetParams = JsonObject()
            reviewerModelSetParams.put("agentId", JsonString("team-reviewer"))
            reviewerModelSetParams.put("state", reviewerState)
            @Expect(handleGatewayAgentsFamily("agents.models.set", request: Some(GatewayRpcRequest("agents.models.set", params: reviewerModelSetParams))).getOrThrow().ok, true)

            File.writeTo(
                home.join("agents").join("user-writer").join("agent").join("auth-profiles.json"),
                "{\"profiles\":[{\"id\":\"writer-openai\",\"provider\":\"openai\",\"apiKey\":\"writer-secret-never-log\"}]}\n".toArray()
            )
            let writerGetParams = JsonObject()
            writerGetParams.put("agentId", JsonString("user-writer"))
            let writerModels = handleGatewayAgentsFamily("agents.models.get", request: Some(GatewayRpcRequest("agents.models.get", params: writerGetParams))).getOrThrow().result.asObject().get("models").getOrThrow().asObject()
            let writerSource = agentsTestObject(writerModels, "credentialSource")
            @Expect(agentsTestString(writerSource, "source"), "agent.auth-profiles.openai")

            let reviewerGetParams = JsonObject()
            reviewerGetParams.put("agentId", JsonString("team-reviewer"))
            let reviewerModels = handleGatewayAgentsFamily("agents.models.get", request: Some(GatewayRpcRequest("agents.models.get", params: reviewerGetParams))).getOrThrow().result.asObject().get("models").getOrThrow().asObject()
            let reviewerSource = agentsTestObject(reviewerModels, "credentialSource")
            @Expect(agentsTestString(reviewerSource, "source"), "unconfigured")
            let renderedModels = writerModels.toJsonString() + reviewerModels.toJsonString()
            @Expect(renderedModels.contains("writer-secret-never-log"), false)

            let deleteParams = JsonObject()
            deleteParams.put("id", JsonString("phase2"))
            let deleteResponse = handleGatewayAgentsFamily("agents.teams.delete", request: Some(GatewayRpcRequest("agents.teams.delete", params: deleteParams))).getOrThrow()
            @Expect(deleteResponse.ok, true)
            let semantics = agentsTestObject(deleteResponse.result.asObject(), "semantics")
            @Expect(agentsTestBool(semantics, "deletePreservesMemberAgents"), true)
            @Expect(exists(userWorkspace.join("USER.md")), true)
            @Expect(exists(home.join("agents").join("team-reviewer").join("agent").join("AGENT.md")), true)
            @Expect(exists(home.join("workspaces").join("team-reviewer").join("SOUL.md")), true)
        })
    }

    @TestCase
    public func agentTeamsCreateUpdateListAndDeleteRoundTripConfig(): Unit {
        withAgentsTempHome("metis-agent-teams-phase7-home", { home: Path =>
            let createParams = JsonObject()
            createParams.put("id", JsonString("content"))
            createParams.put("displayName", JsonString("Content Team"))
            createParams.put("template", JsonString("pm-writer-reviewer"))
            let createResponse = handleGatewayAgentsFamily("agents.teams.create", request: Some(GatewayRpcRequest("agents.teams.create", params: createParams))).getOrThrow()
            @Expect(createResponse.ok, true)
            let created = createResponse.result.asObject().get("team").getOrThrow().asObject()
            @Expect(agentsTestString(created, "id"), "content")
            @Expect(agentsTestString(created, "defaultAgentId"), "content-pm")
            @Expect(exists(home.join("agents").join("content-pm").join("agent").join("AGENT.md")), true)
            @Expect(exists(home.join("agents").join("content-writer").join("agent").join("AGENT.md")), true)
            @Expect(exists(home.join("workspaces").join("content-reviewer").join("IDENTITY.md")), true)

            let listResponse = handleGatewayAgentsFamily("agents.teams.list").getOrThrow()
            @Expect(listResponse.ok, true)
            let teams = listResponse.result.asObject().get("teams").getOrThrow().asArray()
            @Expect(teams.size(), 1)

            let alias = JsonObject()
            alias.put("alias", JsonString("/agent writer"))
            alias.put("agentId", JsonString("content-writer"))
            let aliases = JsonArray([])
            aliases.add(alias)
            let updateParams = JsonObject()
            updateParams.put("id", JsonString("content"))
            updateParams.put("aliases", aliases)
            let updateResponse = handleGatewayAgentsFamily("agents.teams.update", request: Some(GatewayRpcRequest("agents.teams.update", params: updateParams))).getOrThrow()
            @Expect(updateResponse.ok, true)

            let writerParams = JsonObject()
            writerParams.put("agentId", JsonString("content-writer"))
            let writerResponse = handleGatewayAgentsFamily("agent.get", request: Some(GatewayRpcRequest("agent.get", params: writerParams))).getOrThrow()
            let writer = writerResponse.result.asObject().get("agent").getOrThrow().asObject()
            @Expect(agentsTestObjectArrayContainsString(writer, "aliases", "/agent writer"), true)
            @Expect(agentsTestObjectArrayContainsString(writer, "teamIds", "content"), true)

            let deleteParams = JsonObject()
            deleteParams.put("id", JsonString("content"))
            let deleteResponse = handleGatewayAgentsFamily("agents.teams.delete", request: Some(GatewayRpcRequest("agents.teams.delete", params: deleteParams))).getOrThrow()
            @Expect(deleteResponse.ok, true)
            let emptyList = handleGatewayAgentsFamily("agents.teams.list").getOrThrow().result.asObject().get("teams").getOrThrow().asArray()
            @Expect(emptyList.size(), 0)
            @Expect(exists(home.join("agents").join("content-writer").join("agent").join("AGENT.md")), true)
        })
    }
}
