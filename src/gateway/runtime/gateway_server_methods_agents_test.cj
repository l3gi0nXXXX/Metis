package metis.gateway.runtime

import metis.core.config.{CliConfig, CliSettingManager, MetisConfigManager}

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
}
