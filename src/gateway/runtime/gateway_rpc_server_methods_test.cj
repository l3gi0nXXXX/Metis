package metis.gateway.runtime

import metis.core.skills.setClawHubHttpGetForTest
import metis.core.config.{CliConfig, CliSettingManager, MetisConfigManager, MetisProcessEnvironmentLock}
import metis.gateway.logging.{MetisLogEvent, gatewayLoggingResetForTest, metisCreateSubsystemLogger}

import std.env.{getVariable, setVariable}
import std.fs.{Directory, Path, remove}
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonBool, JsonInt, JsonObject, JsonString}

private func gatewayRpcTestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func gatewayRpcRestoreEnv(name: String, oldValue: Option<String>): Unit {
    match (oldValue) {
        case Some(value) => setVariable(name, value)
        case None => setVariable(name, "")
    }
}

private func withGatewayRpcTestHome<T>(label: String, block: () -> T): T {
    synchronized(MetisProcessEnvironmentLock) {
        let home = Path("/tmp/metis-gateway-rpc-${label}-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        try { remove(home, recursive: true) } catch (_: Exception) { () }
        Directory.create(home, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", home.toString())
        CliConfig.invalidatePathCache()
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
        try {
            return block()
        } finally {
            match (oldHome) {
                case Some(value) => setVariable("METIS_HOME", value)
                case None => setVariable("METIS_HOME", "")
            }
            CliConfig.invalidatePathCache()
            MetisConfigManager.invalidate()
            CliSettingManager.invalidate()
            try { remove(home, recursive: true) } catch (_: Exception) { () }
        }
    }
}

private func gatewayRpcInstallRedactionConfig(): Unit {
    let root = JsonObject()
    let gateway = JsonObject()
    let feishu = JsonObject()
    feishu.put("enabled", JsonBool(false))
    feishu.put("appId", JsonString("rpc-feishu-app"))
    feishu.put("appSecret", JsonString("rpc-feishu-secret-never-visible"))
    gateway.put("feishu", feishu)
    let telegram = JsonObject()
    telegram.put("enabled", JsonBool(false))
    telegram.put("botToken", JsonString("rpc-telegram-token-never-visible"))
    gateway.put("telegram", telegram)
    root.put("gateway", gateway)
    MetisConfigManager.writeRoot(root)
    CliConfig.invalidatePathCache()
    MetisConfigManager.invalidate()
    CliSettingManager.invalidate()
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
    public func localDispatcherCoversPhase9UiContractsWithoutSecretLeakage(): Unit {
        withGatewayRpcTestHome("phase9-contracts", { =>
            gatewayRpcInstallRedactionConfig()
            let createParams = JsonObject()
            createParams.put("id", JsonString("content"))
            createParams.put("template", JsonString("pm-writer-reviewer"))
            let create = gatewayDispatchLocalMethod(GatewayRpcRequest("agents.teams.create", params: createParams))
            @Expect(create.ok, true)

            let list = gatewayDispatchLocalMethod(GatewayRpcRequest("agents.teams.list"))
            @Expect(list.ok, true)
            @Expect(list.result.asObject().get("teams").getOrThrow().asArray().size(), 1)

            let getParams = JsonObject()
            getParams.put("id", JsonString("content"))
            let get = gatewayDispatchLocalMethod(GatewayRpcRequest("agents.teams.get", params: getParams))
            @Expect(get.ok, true)
            @Expect(gatewayRpcTestString(get.result.asObject().get("team").getOrThrow().asObject(), "id"), "content")

            let updateParams = JsonObject()
            updateParams.put("id", JsonString("content"))
            updateParams.put("displayName", JsonString("Content Desk"))
            let update = gatewayDispatchLocalMethod(GatewayRpcRequest("agents.teams.update", params: updateParams))
            @Expect(update.ok, true)
            @Expect(gatewayRpcTestString(update.result.asObject().get("team").getOrThrow().asObject(), "displayName"), "Content Desk")

            let status = gatewayDispatchLocalMethod(GatewayRpcRequest("channels.status"))
            @Expect(status.ok, true)
            @Expect(status.result.asObject().get("channelMeta").isSome(), true)

            let runtime = gatewayDispatchLocalMethod(GatewayRpcRequest("agents.runtime.profile"))
            @Expect(runtime.ok, true)
            @Expect(runtime.result.asObject().get("runtime").getOrThrow().asObject().get("authorizationProfile").isSome(), true)

            let auth = gatewayDispatchLocalMethod(GatewayRpcRequest("control_ui.auth"))
            @Expect(auth.ok, true)
            @Expect(auth.result.asObject().get("auth").isSome(), true)

            let doctor = gatewayDispatchLocalMethod(GatewayRpcRequest("doctor"))
            @Expect(doctor.ok, true)
            @Expect(doctor.result.asObject().get("doctor").isSome(), true)

            let delete = gatewayDispatchLocalMethod(GatewayRpcRequest("agents.teams.delete", params: getParams))
            @Expect(delete.ok, true)
            @Expect(gatewayDispatchLocalMethod(GatewayRpcRequest("agents.teams.list")).result.asObject()
                .get("teams").getOrThrow().asArray().size(), 0)

            let rendered = status.toJson().toJsonString() + runtime.toJson().toJsonString() +
                auth.toJson().toJsonString() + doctor.toJson().toJsonString()
            @Expect(rendered.contains("rpc-feishu-secret-never-visible"), false)
            @Expect(rendered.contains("rpc-telegram-token-never-visible"), false)
            @Expect(rendered.contains("Bearer rpc-feishu-secret-never-visible"), false)
            @Expect(rendered.contains("Bearer rpc-telegram-token-never-visible"), false)
        })
    }

    @TestCase
    public func logsRpcTailUsesCurrentLoggingFile(): Unit {
        withGatewayRpcTestHome("logs-rpc", { =>
            let oldLogLevel = getVariable("METIS_LOG_LEVEL")
            let oldLogFile = getVariable("METIS_LOG_FILE")
            let oldConsoleLevel = getVariable("METIS_CONSOLE_LEVEL")
            let logFile = CliConfig.logsDir.join("phase9-rpc.log").toString()
            try {
                setVariable("METIS_LOG_LEVEL", "info")
                setVariable("METIS_LOG_FILE", logFile)
                setVariable("METIS_CONSOLE_LEVEL", "silent")
                gatewayLoggingResetForTest()

                metisCreateSubsystemLogger("gateway").info(MetisLogEvent.gatewayReady, "rpc log ready")

                let params = JsonObject()
                params.put("file", JsonString(logFile))
                params.put("limit", JsonInt(10))
                params.put("cursor", JsonInt(-1))
                let tail = gatewayDispatchLocalMethod(GatewayRpcRequest("logs.tail", params: params))
                @Expect(tail.ok, true)
                let tailResult = tail.result.asObject()
                @Expect(gatewayRpcTestString(tailResult, "file"), logFile)
                @Expect(tailResult.get("cursor").isSome(), true)
                @Expect(tailResult.get("size").isSome(), true)
                @Expect(tailResult.get("truncated").isSome(), true)
                @Expect(tailResult.get("reset").isSome(), true)
                let lines = tailResult.get("lines").getOrThrow().asArray()
                @Expect(lines.size() >= 1, true)
                @Expect(tailResult.toJsonString().contains("rpc log ready"), true)
            } finally {
                gatewayRpcRestoreEnv("METIS_LOG_LEVEL", oldLogLevel)
                gatewayRpcRestoreEnv("METIS_LOG_FILE", oldLogFile)
                gatewayRpcRestoreEnv("METIS_CONSOLE_LEVEL", oldConsoleLevel)
                gatewayLoggingResetForTest()
            }
        })
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
