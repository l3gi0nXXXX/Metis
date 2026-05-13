package metis.gateway.runtime

import magic.jsonable.*

import metis.core.gatewaySubagentResolveAgent
import metis.core.config.{CliConfig, CliModelRuntimeStateManager, CliSettingManager, MetisConfigManager, MetisProcessEnvironmentLock}
import metis.gateway.core.{GatewayAgentRouteInput, gatewayResolveAgentRoute}

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
    public func agentFilesRpcUsesWorkspaceSafeBootstrapFiles(): Unit {
        withAgentsTempHome("metis-agents-files-phase7-home", { home: Path =>
            let addParams = JsonObject()
            addParams.put("id", JsonString("pm"))
            let addResponse = handleGatewayAgentsFamily("agents.add", request: Some(GatewayRpcRequest("agents.add", params: addParams))).getOrThrow()
            @Expect(addResponse.ok, true)

            let listParams = JsonObject()
            listParams.put("agentId", JsonString("pm"))
            let listResponse = handleGatewayAgentsFamily("agents.files.list", request: Some(GatewayRpcRequest("agents.files.list", params: listParams))).getOrThrow()
            @Expect(listResponse.ok, true)
            let listResult = listResponse.result.asObject()
            @Expect(agentsTestString(listResult, "workspace"), home.join("workspaces").join("pm").toString())
            let files = listResult.get("files").getOrThrow().asArray()
            let soulRow = agentsTestFindObjectById(files, "SOUL.md")
            @Expect(agentsTestString(soulRow, "name"), "SOUL.md")
            @Expect(agentsTestBool(soulRow, "missing"), false)

            let setParams = JsonObject()
            setParams.put("agentId", JsonString("pm"))
            setParams.put("name", JsonString("SOUL.md"))
            setParams.put("content", JsonString("# Soul\n\ncustom soul\n"))
            let setResponse = handleGatewayAgentsFamily("agents.files.set", request: Some(GatewayRpcRequest("agents.files.set", params: setParams))).getOrThrow()
            @Expect(setResponse.ok, true)
            let file = setResponse.result.asObject().get("file").getOrThrow().asObject()
            @Expect(agentsTestString(file, "content"), "# Soul\n\ncustom soul\n")

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
