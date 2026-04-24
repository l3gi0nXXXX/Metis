package metis.gateway.runtime

import metis.core.skills.setClawHubHttpGetForTest

import std.unittest.testmacro.*
import stdx.encoding.json.{JsonObject, JsonString}

private func gatewayRpcTestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

@Test
public class GatewayRpcServerMethodsTest {
    @TestCase
    public func localDispatcherRoutesSkillsStatusToSkillsFamily(): Unit {
        let response = gatewayDispatchLocalMethod(GatewayRpcRequest("skills.status"))
        @Expect(response.ok, true)
        let result = response.result.asObject()
        @Expect(result.get("skills").isSome(), true)
        @Expect(result.get("workspaceDir").isSome(), true)
    }

    @TestCase
    public func localDispatcherRoutesSkillsDetailToSkillsFamily(): Unit {
        try {
            setClawHubHttpGetForTest(Some({ _url: String =>
                "{\"skill\":{\"slug\":\"weather\",\"displayName\":\"Weather\"},\"latestVersion\":{\"version\":\"1.2.3\"}}"
            }))
            let params = JsonObject()
            params.put("slug", JsonString("weather"))
            let response = gatewayDispatchLocalMethod(GatewayRpcRequest("skills.detail", params: params))
            @Expect(response.ok, true)
            let skill = response.result.asObject().get("skill").getOrThrow().asObject()
            @Expect(gatewayRpcTestString(skill, "slug"), "weather")
        } finally {
            setClawHubHttpGetForTest(None)
        }
    }

    @TestCase
    public func localDispatcherRoutesSkillsSearchAndUpdateToSkillsFamily(): Unit {
        try {
            setClawHubHttpGetForTest(Some({ _url: String =>
                "{\"results\":[{\"slug\":\"weather\",\"displayName\":\"Weather\",\"summary\":\"forecast\"}]}"
            }))
            let searchParams = JsonObject()
            searchParams.put("query", JsonString("weather"))
            let searchResponse = gatewayDispatchLocalMethod(GatewayRpcRequest("skills.search", params: searchParams))
            @Expect(searchResponse.ok, true)
            let results = searchResponse.result.asObject().get("results").getOrThrow().asArray()
            @Expect(results.size(), 1)
        } finally {
            setClawHubHttpGetForTest(None)
        }

        let updateParams = JsonObject()
        updateParams.put("skillKey", JsonString("review"))
        updateParams.put("apiKey", JsonString("abc\r\ndef"))
        let env = JsonObject()
        env.put(" OPENAI_API_KEY ", JsonString(" sk-test "))
        updateParams.put("env", env)
        let updateResponse = gatewayDispatchLocalMethod(GatewayRpcRequest("skills.update", params: updateParams))
        @Expect(updateResponse.ok, true)
        let config = updateResponse.result.asObject().get("config").getOrThrow().asObject()
        @Expect(gatewayRpcTestString(config, "apiKey"), "abcdef")
        let savedEnv = config.get("env").getOrThrow().asObject()
        @Expect(gatewayRpcTestString(savedEnv, "OPENAI_API_KEY"), "sk-test")
    }

    @TestCase
    public func localDispatcherRoutesSkillsCompatibilityMatrixToSkillsFamily(): Unit {
        let response = gatewayDispatchLocalMethod(GatewayRpcRequest("skills.compatibilityMatrix"))
        @Expect(response.ok, true)
        let result = response.result.asObject()
        @Expect(gatewayRpcTestString(result, "kind"), "skills-compatibility-matrix")
        @Expect(result.get("summary").isSome(), true)
    }

    @TestCase
    public func localDispatcherRoutesAgentsRuntimeProfileToUnifiedGatewayRuntimeSurface(): Unit {
        let response = gatewayDispatchLocalMethod(GatewayRpcRequest("agents.runtime.profile"))
        @Expect(response.ok, true)
        let result = response.result.asObject()
        let runtime = result.get("runtime").getOrThrow().asObject()
        @Expect(gatewayRpcTestString(runtime, "kind"), "gateway-main-runtime-profile")
        @Expect(runtime.get("requiredCoreTools").isSome(), true)
        @Expect(runtime.get("currentTools").isSome(), true)
        @Expect(runtime.get("effectiveTools").isSome(), true)
        @Expect(runtime.get("missingCoreTools").isSome(), true)
        @Expect(runtime.get("extendedSurfaceTools").isSome(), true)
        @Expect(runtime.get("missingExtendedSurfaceTools").isSome(), true)
        @Expect(runtime.get("authorizationProfile").isSome(), true)
        @Expect(runtime.get("ingresses").isSome(), true)
        let currentTools = runtime.get("currentTools").getOrThrow().asArray().toJsonString()
        let effectiveTools = runtime.get("effectiveTools").getOrThrow().asArray().toJsonString()
        @Expect(currentTools.contains("\"process\""), true)
        @Expect(currentTools.contains("\"gateway\""), true)
        @Expect(effectiveTools.contains("\"process\""), true)
        @Expect(effectiveTools.contains("\"gateway\""), true)
        let ingresses = runtime.get("ingresses").getOrThrow().asArray()
        @Expect(ingresses.size() >= 5, true)
        @Expect(runtime.get("coversUnifiedCoreBaseline").getOrThrow().asBool().getValue(), true)
        let firstPromptProfile = ingresses[0].asObject().get("promptProfile").getOrThrow().asObject()
        @Expect(gatewayRpcTestString(firstPromptProfile, "template"), "gateway-im-metis-runtime")
        @Expect(firstPromptProfile.get("sharedBasePrompt").getOrThrow().asBool().getValue(), true)
        let firstAuthorizationProfile = ingresses[0].asObject().get("authorizationProfile").getOrThrow().asObject()
        @Expect(gatewayRpcTestString(firstAuthorizationProfile, "enforcementStage"), "runtime-tool-filter")
        let gatewayActionPolicy = firstAuthorizationProfile.get("gatewayActionPolicy").getOrThrow().asObject()
        @Expect(gatewayRpcTestString(gatewayActionPolicy, "mode"), "owner-policy-approval-protected-path")
        @Expect(gatewayActionPolicy.get("autoOwnerApprovedSources").getOrThrow().asArray().toJsonString().contains("\"cli\""), true)
        @Expect(gatewayActionPolicy.get("ownerAuthorizationSignals").getOrThrow().asArray().toJsonString().contains("\"operator-scopes\""), true)
        @Expect(gatewayRpcTestString(gatewayActionPolicy, "ownerInferenceMode"), "runtime-ingress-derived")
    }

    @TestCase
    public func localDispatcherRoutesDashboardAgentsRuntimeToDashboardConsumerSurface(): Unit {
        let response = gatewayDispatchLocalMethod(GatewayRpcRequest("dashboard.agents.runtime"))
        @Expect(response.ok, true)
        let result = response.result.asObject()
        let runtime = result.get("runtime").getOrThrow().asObject()
        @Expect(gatewayRpcTestString(runtime, "kind"), "gateway-main-runtime-profile")
        @Expect(runtime.get("coversUnifiedCoreBaseline").getOrThrow().asBool().getValue(), true)
        @Expect(runtime.get("effectiveTools").isSome(), true)
        @Expect(runtime.get("authorizationProfile").isSome(), true)
        let effectiveTools = runtime.get("effectiveTools").getOrThrow().asArray().toJsonString()
        @Expect(effectiveTools.contains("\"process\""), true)
        @Expect(effectiveTools.contains("\"gateway\""), true)
        let ingresses = runtime.get("ingresses").getOrThrow().asArray()
        @Expect(ingresses.size() >= 5, true)
        let firstPromptProfile = ingresses[0].asObject().get("promptProfile").getOrThrow().asObject()
        @Expect(gatewayRpcTestString(firstPromptProfile, "template"), "gateway-im-metis-runtime")
        @Expect(firstPromptProfile.get("sharedBasePrompt").getOrThrow().asBool().getValue(), true)
        let firstAuthorizationProfile = ingresses[0].asObject().get("authorizationProfile").getOrThrow().asObject()
        @Expect(gatewayRpcTestString(firstAuthorizationProfile, "enforcementStage"), "runtime-tool-filter")
        let gatewayActionPolicy = firstAuthorizationProfile.get("gatewayActionPolicy").getOrThrow().asObject()
        @Expect(gatewayRpcTestString(gatewayActionPolicy, "mode"), "owner-policy-approval-protected-path")
        @Expect(gatewayActionPolicy.get("autoOwnerApprovedSources").getOrThrow().asArray().toJsonString().contains("\"dashboard\""), true)
        @Expect(gatewayActionPolicy.get("contextIdentityFields").getOrThrow().asArray().toJsonString().contains("\"declaredUser\""), true)
        @Expect(gatewayRpcTestString(gatewayActionPolicy, "explicitRequestInference"), "runtime-context-prompt-derived")
    }

    @TestCase
    public func localDispatcherRoutesAgentsRuntimeAuditToClosureSurface(): Unit {
        let response = gatewayDispatchLocalMethod(GatewayRpcRequest("agents.runtime.audit"))
        @Expect(response.ok, true)
        let result = response.result.asObject()
        let audit = result.get("audit").getOrThrow().asObject()
        @Expect(gatewayRpcTestString(audit, "kind"), "gateway-main-runtime-audit")
        let summary = audit.get("summary").getOrThrow().asObject()
        @Expect(gatewayRpcTestString(summary, "phase"), "G8")
        let closure = summary.get("closure").getOrThrow().asObject()
        @Expect(closure.get("defaultIngressesShareGatewayMain").getOrThrow().asBool().getValue(), true)
        let consumers = summary.get("consumers").getOrThrow().asObject()
        @Expect(consumers.get("controlUiHttpAudit").getOrThrow().asBool().getValue(), true)
        let runtime = audit.get("runtime").getOrThrow().asObject()
        @Expect(runtime.get("effectiveTools").isSome(), true)
        @Expect(runtime.get("authorizationProfile").getOrThrow().asObject().get("gatewayActionPolicy").isSome(), true)
        let effectiveTools = runtime.get("effectiveTools").getOrThrow().asArray().toJsonString()
        @Expect(effectiveTools.contains("\"process\""), true)
        @Expect(effectiveTools.contains("\"gateway\""), true)
    }

    @TestCase
    public func localDispatcherRoutesDashboardAgentsRuntimeAuditToDashboardClosureSurface(): Unit {
        let response = gatewayDispatchLocalMethod(GatewayRpcRequest("dashboard.agents.runtime.audit"))
        @Expect(response.ok, true)
        let result = response.result.asObject()
        let audit = result.get("audit").getOrThrow().asObject()
        @Expect(gatewayRpcTestString(audit, "kind"), "gateway-main-runtime-audit")
        let summary = audit.get("summary").getOrThrow().asObject()
        @Expect(gatewayRpcTestString(summary, "phase"), "G8")
        let consumers = summary.get("consumers").getOrThrow().asObject()
        @Expect(consumers.get("dashboardAgentsRuntimeAudit").getOrThrow().asBool().getValue(), true)
    }

    @TestCase
    public func localDispatcherRoutesChannelsAuditToTelegramClosureSurface(): Unit {
        let params = JsonObject()
        params.put("channelId", JsonString("telegram"))
        let response = gatewayDispatchLocalMethod(GatewayRpcRequest("channels.audit", params: params))
        @Expect(response.ok, true)
        let result = response.result.asObject()
        let audit = result.get("audit").getOrThrow().asObject()
        @Expect(gatewayRpcTestString(audit, "kind"), "gateway-channels-audit")
        let summary = audit.get("summary").getOrThrow().asObject()
        @Expect(gatewayRpcTestString(summary, "phase"), "T12")
        let closure = summary.get("closure").getOrThrow().asObject()
        @Expect(closure.get("telegramThreadBindingVisibleInControlUiSessions").getOrThrow().asBool().getValue(), true)
        @Expect(closure.get("telegramReactionRuntimeVisible").getOrThrow().asBool().getValue(), true)
        let consumers = summary.get("consumers").getOrThrow().asObject()
        @Expect(consumers.get("mcpOverHttp").getOrThrow().asBool().getValue(), true)
        let runtime = audit.get("runtime").getOrThrow().asObject()
        let telegram = runtime.get("telegram").getOrThrow().asObject()
        @Expect(telegram.get("registrationPayload").isSome(), true)
        @Expect(telegram.get("healthSnapshot").isSome(), true)
    }
}
