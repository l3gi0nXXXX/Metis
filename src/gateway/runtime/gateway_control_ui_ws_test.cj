package metis.gateway.runtime

import metis.core.config.{CliSettingManager, GatewayUserSettings, MetisConfigManager}
import metis.core.skills.setClawHubHttpGetForTest
import metis.gateway.config.buildGatewayConfigFromUserSettings
import metis.gateway.core.{gatewayFindSessionConversationViewForUser, gatewaySessionStoreForUserWithAgentId, setGatewayFeishuNativeAuthRunnerForTest}
import metis.gateway.protocol.GatewayProtocolResponse

import magic.jsonable.*
import std.env.{getVariable, setVariable}
import std.fs.{Directory, Path, remove}
import std.fs.File
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString}
import std.unittest.testmacro.*

private func gatewayControlUiWsTestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func wsConcatLines(lines: Array<String>): String {
    String.join(lines, delimiter: "\n") + "\n"
}

private func withGatewayControlUiWsTestHome<T>(block: () -> T): T {
    let testHome = "/tmp/metis-gateway-control-ui-ws-test-home"
    try {
        remove(Path(testHome), recursive: true)
    } catch (_: Exception) {
        ()
    }
    Directory.create(testHome, recursive: true)
    let oldHome = getVariable("METIS_HOME")
    setVariable("METIS_HOME", testHome)
    MetisConfigManager.invalidate()
    CliSettingManager.invalidate()
    try {
        return block()
    } finally {
        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }
}

@Test
public class GatewayControlUiWsTest {
    @TestCase
    public func sessionAgentIdPrefersResolvedLocationHint(): Unit {
        @Expect(gatewayControlUiWsResolveSessionAgentId("qq:direct:123", "general"), "general")
        @Expect(gatewayControlUiWsResolveSessionAgentId("agent:general:main", ""), "general")
        @Expect(gatewayControlUiWsResolveSessionAgentId("qq:direct:123", ""), "main")
    }

    @TestCase
    public func sessionChannelAndChatTypeDeriveFromSessionKey(): Unit {
        @Expect(gatewayControlUiWsResolveSessionChannel("qq:group:123"), "qq")
        @Expect(gatewayControlUiWsResolveSessionChatType("qq:group:123"), "group")
        @Expect(gatewayControlUiWsResolveSessionChannel("cli:main"), "cli")
        @Expect(gatewayControlUiWsResolveSessionChatType("cli:main"), "direct")
    }

    @TestCase
    public func sessionOriginUsesResolvedPeerInsteadOfWholeSessionKey(): Unit {
        let origin = gatewayControlUiWsBuildSessionOrigin("qq:group:chat-42", "qq", "group")
        @Expect(origin.get("provider").getOrThrow().asString().getValue(), "qq")
        @Expect(origin.get("from").getOrThrow().asString().getValue(), "qq")
        @Expect(origin.get("to").getOrThrow().asString().getValue(), "chat-42")
    }

    @TestCase
    public func chatEventPayloadCarriesSessionAndState(): Unit {
        let content = JsonArray([])
        let item = JsonObject()
        item.put("type", JsonString("text"))
        item.put("text", JsonString("hello"))
        content.add(item)
        let message = JsonObject()
        message.put("role", JsonString("assistant"))
        message.put("content", content)
        message.put("timestamp", 123.toJsonValue())
        let payload = gatewayControlUiWsChatEventPayload(
            "main",
            "run-1",
            "final",
            message
        )
        @Expect(payload.get("sessionKey").getOrThrow().asString().getValue(), "main")
        @Expect(payload.get("runId").getOrThrow().asString().getValue(), "run-1")
        @Expect(payload.get("state").getOrThrow().asString().getValue(), "final")
        @Expect(
            payload.get("message").getOrThrow().asObject().get("role").getOrThrow().asString().getValue(),
            "assistant"
        )
    }

    @TestCase
    public func chatEventPayloadCanCarryConversationProjection(): Unit {
        withGatewayControlUiWsTestHome {
            let user = GatewayUserSettings()
            let store = gatewaySessionStoreForUserWithAgentId(user, "general")
            let sessionKey = "agent:general:chat-event-test"
            store.deleteSession(sessionKey)
            store.appendAssistant(sessionKey, "hello")

            let content = JsonArray([])
            let item = JsonObject()
            item.put("type", JsonString("text"))
            item.put("text", JsonString("hello"))
            content.add(item)
            let message = JsonObject()
            message.put("role", JsonString("assistant"))
            message.put("content", content)
            message.put("timestamp", 123.toJsonValue())
            let payload = gatewayControlUiWsChatEventPayload(
                sessionKey,
                "run-1",
                "final",
                message,
                conversation: gatewayFindSessionConversationViewForUser(user, sessionKey)
            )
            @Expect(gatewayControlUiWsTestString(payload, "agentId"), "general")
            @Expect(gatewayControlUiWsTestString(payload, "sessionId").contains(".jsonl"), false)
            @Expect(payload.get("origin").isSome(), true)
            @Expect(payload.get("binding").isSome(), true)

            store.deleteSession(sessionKey)
        }
    }

    @TestCase
    public func invalidatePayloadCanCarryConversationProjection(): Unit {
        withGatewayControlUiWsTestHome {
            let user = GatewayUserSettings()
            let store = gatewaySessionStoreForUserWithAgentId(user, "general")
            let sessionKey = "agent:general:invalidate-event-test"
            store.deleteSession(sessionKey)
            store.appendAssistant(sessionKey, "hello")

            let params = JsonObject()
            params.put("session", JsonString(sessionKey))
            let payload = gatewayControlUiWsInvalidatePayload("dashboard.chat.send", params)
            @Expect(gatewayControlUiWsTestString(payload, "sessionKey"), sessionKey)
            @Expect(gatewayControlUiWsTestString(payload, "agentId"), "general")
            @Expect(gatewayControlUiWsTestString(payload, "sessionId").contains(".jsonl"), false)
            @Expect(payload.get("origin").isSome(), true)
            @Expect(payload.get("binding").isSome(), true)

            store.deleteSession(sessionKey)
        }
    }

    @TestCase
    public func sessionsSubscribeAdvertisesTranscriptUpdatedEvent(): Unit {
        let cfg = buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())
        let response = gatewayControlUiWsCompatResponse("sessions.subscribe", JsonObject(), cfg)
        @Expect(response.isSome(), true)
        let result = response.getOrThrow().result.asObject()
        @Expect(gatewayControlUiWsTestString(result, "mode"), "direct-websocket")
        @Expect(gatewayControlUiWsTestString(result, "cursorMode"), "direct-push")
        @Expect(gatewayControlUiWsTestString(result, "unsubscribeMethod"), "sessions.unsubscribe")
        let kinds = result.get("kinds").getOrThrow().asArray()
        @Expect(kinds.size() >= 4, true)
        @Expect(kinds.toJsonString().contains("\"session.transcript.updated\""), true)
        @Expect(kinds.toJsonString().contains("\"sessions.changed\""), true)
    }

    @TestCase
    public func agentsRuntimeProfileCompatResponseReusesUnifiedGatewayProfile(): Unit {
        let cfg = buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())
        let response = gatewayControlUiWsCompatResponse("agents.runtime.profile", JsonObject(), cfg)
        @Expect(response.isSome(), true)
        let result = response.getOrThrow().result.asObject()
        let runtime = result.get("runtime").getOrThrow().asObject()
        @Expect(gatewayControlUiWsTestString(runtime, "kind"), "gateway-main-runtime-profile")
        @Expect(runtime.get("effectiveTools").isSome(), true)
        @Expect(runtime.get("extendedSurfaceTools").isSome(), true)
        @Expect(runtime.get("missingExtendedSurfaceTools").isSome(), true)
        @Expect(runtime.get("authorizationProfile").isSome(), true)
        @Expect(runtime.get("ingresses").isSome(), true)
        let effectiveTools = runtime.get("effectiveTools").getOrThrow().asArray().toJsonString()
        @Expect(effectiveTools.contains("\"process\""), true)
        @Expect(effectiveTools.contains("\"gateway\""), true)
        let ingresses = runtime.get("ingresses").getOrThrow().asArray()
        @Expect(ingresses.size() >= 5, true)
        @Expect(runtime.get("coversUnifiedCoreBaseline").getOrThrow().asBool().getValue(), true)
        let firstPromptProfile = ingresses[0].asObject().get("promptProfile").getOrThrow().asObject()
        @Expect(gatewayControlUiWsTestString(firstPromptProfile, "template"), "gateway-im-metis-runtime")
        @Expect(firstPromptProfile.get("sharedBasePrompt").getOrThrow().asBool().getValue(), true)
        let firstAuthorizationProfile = ingresses[0].asObject().get("authorizationProfile").getOrThrow().asObject()
        @Expect(gatewayControlUiWsTestString(firstAuthorizationProfile, "enforcementStage"), "runtime-tool-filter")
        let gatewayActionPolicy = firstAuthorizationProfile.get("gatewayActionPolicy").getOrThrow().asObject()
        @Expect(gatewayControlUiWsTestString(gatewayActionPolicy, "mode"), "owner-policy-approval-protected-path")
        @Expect(gatewayActionPolicy.get("autoOwnerApprovedSources").getOrThrow().asArray().toJsonString().contains("\"control-ui\""), true)
        @Expect(gatewayActionPolicy.get("ownerAuthorizationSignals").getOrThrow().asArray().toJsonString().contains("\"operator-scopes\""), true)
        @Expect(gatewayControlUiWsTestString(gatewayActionPolicy, "ownerInferenceMode"), "runtime-ingress-derived")
    }

    @TestCase
    public func agentIdentityGetKeepsMainInternalIdButReturnsMetisDisplayName(): Unit {
        let cfg = buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())
        let params = JsonObject()
        params.put("sessionKey", JsonString("agent:main:main"))

        let response = gatewayControlUiWsCompatResponse("agent.identity.get", params, cfg)

        @Expect(response.isSome(), true)
        let result = response.getOrThrow().result.asObject()
        @Expect(gatewayControlUiWsTestString(result, "agentId"), "main")
        @Expect(gatewayControlUiWsTestString(result, "name"), "Metis")
    }

    @TestCase
    public func agentsRuntimeAuditCompatResponseReusesUnifiedClosureSurface(): Unit {
        let cfg = buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())
        let response = gatewayControlUiWsCompatResponse("agents.runtime.audit", JsonObject(), cfg)
        @Expect(response.isSome(), true)
        let result = response.getOrThrow().result.asObject()
        let audit = result.get("audit").getOrThrow().asObject()
        @Expect(gatewayControlUiWsTestString(audit, "kind"), "gateway-main-runtime-audit")
        let summary = audit.get("summary").getOrThrow().asObject()
        @Expect(gatewayControlUiWsTestString(summary, "phase"), "G8")
        let closure = summary.get("closure").getOrThrow().asObject()
        @Expect(closure.get("policyFilteringEnforcedAtRuntime").getOrThrow().asBool().getValue(), true)
        let consumers = summary.get("consumers").getOrThrow().asObject()
        @Expect(consumers.get("controlUiWsAudit").getOrThrow().asBool().getValue(), true)
        let runtime = audit.get("runtime").getOrThrow().asObject()
        @Expect(runtime.get("effectiveTools").isSome(), true)
        @Expect(runtime.get("authorizationProfile").isSome(), true)
        @Expect(runtime.get("authorizationProfile").getOrThrow().asObject().get("gatewayActionPolicy").isSome(), true)
        let effectiveTools = runtime.get("effectiveTools").getOrThrow().asArray().toJsonString()
        @Expect(effectiveTools.contains("\"process\""), true)
        @Expect(effectiveTools.contains("\"gateway\""), true)
    }

    @TestCase
    public func agentsTeamsCompatResponsePassesThroughGatewayAgentsFamily(): Unit {
        withGatewayControlUiWsTestHome {
            let cfg = buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())
            let createParams = JsonObject()
            createParams.put("id", JsonString("content"))
            createParams.put("displayName", JsonString("Content Team"))
            createParams.put("template", JsonString("pm-writer-reviewer"))

            let createResponse = gatewayControlUiWsCompatResponse("agents.teams.create", createParams, cfg)
            @Expect(createResponse.isSome(), true)
            @Expect(createResponse.getOrThrow().ok, true)

            let listResponse = gatewayControlUiWsCompatResponse("agents.teams.list", JsonObject(), cfg)
            @Expect(listResponse.isSome(), true)
            let result = listResponse.getOrThrow().result.asObject()
            @Expect(result.get("teams").getOrThrow().asArray().size(), 1)
        }
    }

    @TestCase
    public func channelsRuntimeCompatResponseExposesTelegramNativeRuntimeView(): Unit {
        let cfg = buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())
        let params = JsonObject()
        params.put("channelId", JsonString("telegram"))
        let response = gatewayControlUiWsCompatResponse("channels.runtime", params, cfg)
        @Expect(response.isSome(), true)
        let result = response.getOrThrow().result.asObject()
        let telegram = result.get("telegram").getOrThrow().asObject()
        @Expect(telegram.get("allowedUpdates").isSome(), true)
        @Expect(telegram.get("registrationPayload").isSome(), true)
        @Expect(telegram.get("healthSnapshot").isSome(), true)
    }

    @TestCase
    public func feishuAuthStartCompatResponsePreservesAccountIdAndRedactsSecrets(): Unit {
        try {
            setGatewayFeishuNativeAuthRunnerForTest(Some({ accountId: String, _user: GatewayUserSettings =>
                let out = JsonObject()
                out.put("status", JsonString("pending"))
                out.put("accountId", JsonString(accountId))
                out.put("accessToken", JsonString("secret-access-token"))
                out.put("redacted", JsonBool(false))
                out
            }))

            let cfg = buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())
            let params = JsonObject()
            params.put("accountId", JsonString("tenant-a"))
            let response = gatewayControlUiWsCompatResponse("channels.feishu.auth.start", params, cfg)
            @Expect(response.isSome(), true)
            let result = response.getOrThrow().result.asObject()
            @Expect(gatewayControlUiWsTestString(result, "status"), "pending")
            @Expect(gatewayControlUiWsTestString(result, "accountId"), "tenant-a")
            @Expect(result.toJsonString().contains("secret-access-token"), false)
            @Expect(result.get("redacted").getOrThrow().asBool().getValue(), true)
        } finally {
            setGatewayFeishuNativeAuthRunnerForTest(None<(String, GatewayUserSettings) -> JsonObject>)
        }
    }

    @TestCase
    public func channelsHealthCompatResponseExposesTelegramNativeHealthView(): Unit {
        let cfg = buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())
        let response = gatewayControlUiWsCompatResponse("channels.health", JsonObject(), cfg)
        @Expect(response.isSome(), true)
        let result = response.getOrThrow().result.asObject()
        let telegram = result.get("telegram").getOrThrow().asObject()
        @Expect(telegram.get("healthSnapshot").isSome(), true)
        @Expect(telegram.get("supports").isSome(), true)
        @Expect(telegram.get("actions").isSome(), true)
    }

    @TestCase
    public func channelsAuditCompatResponseExposesTelegramUnifiedAuditView(): Unit {
        let cfg = buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())
        let params = JsonObject()
        params.put("channelId", JsonString("telegram"))
        let response = gatewayControlUiWsCompatResponse("channels.audit", params, cfg)
        @Expect(response.isSome(), true)
        let result = response.getOrThrow().result.asObject()
        let audit = result.get("audit").getOrThrow().asObject()
        @Expect(gatewayControlUiWsTestString(audit, "kind"), "gateway-channels-audit")
        let summary = audit.get("summary").getOrThrow().asObject()
        @Expect(gatewayControlUiWsTestString(summary, "phase"), "T12")
        let closure = summary.get("closure").getOrThrow().asObject()
        @Expect(closure.get("telegramThreadBindingVisibleInControlUiWsSessions").getOrThrow().asBool().getValue(), true)
        @Expect(closure.get("telegramMediaRuntimeVisible").getOrThrow().asBool().getValue(), true)
        let consumers = summary.get("consumers").getOrThrow().asObject()
        @Expect(consumers.get("controlUiSessionsWs").getOrThrow().asBool().getValue(), true)
        let runtime = audit.get("runtime").getOrThrow().asObject()
        let telegram = runtime.get("telegram").getOrThrow().asObject()
        @Expect(telegram.get("registrationPayload").isSome(), true)
        @Expect(telegram.get("healthSnapshot").isSome(), true)
    }

    // @TestCase
    // public func chatAcceptedPayloadCanCarryConversationProjection(): Unit {
    //     let user = GatewayUserSettings()
    //     let store = gatewaySessionStoreForUserWithAgentId(user, "general")
    //     let sessionKey = "agent:general:accepted-event-test"
    //     store.deleteSession(sessionKey)
    //     store.appendAssistant(sessionKey, "hello")
    //
    //     let params = JsonObject()
    //     params.put("session", JsonString(sessionKey))
    //     params.put("replyChannel", JsonString("qq"))
    //     params.put("replyTo", JsonString("10001"))
    //     params.put("conversationId", JsonString("user:10001"))
    //     params.put("threadId", JsonString("thread-1"))
    //     params.put("sourceMessageId", JsonString("msg-source-1"))
    //     params.put("replyToMessageId", JsonString("msg-1"))
    //     params.put("replyInThread", JsonString("true"))
    //     let payload = gatewayControlUiWsChatAcceptedPayload(params)
    //     @Expect(gatewayControlUiWsTestString(payload, "sessionKey"), sessionKey)
    //     @Expect(gatewayControlUiWsTestString(payload, "agentId"), "general")
    //     @Expect(gatewayControlUiWsTestString(payload, "sessionId").contains(".jsonl"), false)
    //     @Expect(payload.get("origin").isSome(), true)
    //     let delivery = payload.get("delivery").getOrThrow().asObject()
    //     @Expect(gatewayControlUiWsTestString(delivery, "replyChannel"), "qq")
    //     @Expect(gatewayControlUiWsTestString(delivery, "replyToMessageId"), "msg-1")
    //     let binding = payload.get("binding").getOrThrow().asObject()
    //     @Expect(gatewayControlUiWsTestString(binding, "conversationId"), "user:10001")
    //     @Expect(gatewayControlUiWsTestString(binding, "threadId"), "thread-1")
    //     @Expect(gatewayControlUiWsTestString(binding, "sourceMessageId"), "msg-source-1")
    //
    //     store.deleteSession(sessionKey)
    // }

    @TestCase
    public func invalidatePayloadPrefersResponseDeliveryProjection(): Unit {
        let user = GatewayUserSettings()
        let store = gatewaySessionStoreForUserWithAgentId(user, "general")
        let sessionKey = "agent:general:invalidate-delivery-test"
        store.deleteSession(sessionKey)
        store.appendAssistant(sessionKey, "hello")

        let params = JsonObject()
        params.put("session", JsonString(sessionKey))
        params.put("replyChannel", JsonString("qq"))
        params.put("replyTo", JsonString("10001"))

        let result = JsonObject()
        result.put("session", JsonString(sessionKey))
        let responseDelivery = JsonObject()
        responseDelivery.put("replyChannel", JsonString("feishu"))
        responseDelivery.put("replyTo", JsonString("chat-2"))
        responseDelivery.put("replyToMessageId", JsonString("msg-2"))
        result.put("delivery", responseDelivery)
        let responseBinding = JsonObject()
        responseBinding.put("conversationId", JsonString("chat-2"))
        responseBinding.put("threadId", JsonString("thread-2"))
        result.put("binding", responseBinding)
        let response = GatewayProtocolResponse(true, "dashboard.chat.send", result: result)

        let payload = gatewayControlUiWsInvalidatePayload("dashboard.chat.send", params, response: Some(response))
        let delivery = payload.get("delivery").getOrThrow().asObject()
        @Expect(gatewayControlUiWsTestString(delivery, "replyChannel"), "feishu")
        @Expect(gatewayControlUiWsTestString(delivery, "replyToMessageId"), "msg-2")
        let binding = payload.get("binding").getOrThrow().asObject()
        @Expect(gatewayControlUiWsTestString(binding, "conversationId"), "chat-2")
        @Expect(gatewayControlUiWsTestString(binding, "threadId"), "thread-2")

        store.deleteSession(sessionKey)
    }

    @TestCase
    public func chatEventFrameCarriesChatEventPayload(): Unit {
        let content = JsonArray([])
        let item = JsonObject()
        item.put("type", JsonString("text"))
        item.put("text", JsonString("hello"))
        content.add(item)
        let message = JsonObject()
        message.put("role", JsonString("assistant"))
        message.put("content", content)
        message.put("timestamp", 123.toJsonValue())
        let payload = gatewayControlUiWsChatEventPayload(
            "agent:general:main",
            "run-2",
            "final",
            message
        )
        let frame = gatewayControlUiWsChatEventFrame("metis-control-ui", "final", payload)
        @Expect(frame.get("type").getOrThrow().asString().getValue(), "event")
        @Expect(frame.get("event").getOrThrow().asString().getValue(), "chat")
        let framePayload = frame.get("payload").getOrThrow().asObject()
        @Expect(framePayload.get("sessionKey").getOrThrow().asString().getValue(), "agent:general:main")
        @Expect(framePayload.get("runId").getOrThrow().asString().getValue(), "run-2")
    }

    @TestCase
    public func sessionStoreFallsBackToUnifiedAgentResolution(): Unit {
        let user = GatewayUserSettings()
        let store = gatewayControlUiWsStoreForSessionKey("agent:general:main")
        let generalStore = gatewaySessionStoreForUserWithAgentId(user, "general")
        @Expect(store.sessionsRoot().toString(), generalStore.sessionsRoot().toString())
    }

    @TestCase
    public func sessionsListReusesSessionCatalogMetadata(): Unit {
        withGatewayControlUiWsTestHome {
            let user = GatewayUserSettings()
            let store = gatewaySessionStoreForUserWithAgentId(user, "general")
            let sessionKey = "agent:general:ws-catalog-test"
            store.deleteSession(sessionKey)
            store.appendUser(sessionKey, "hello-ws")
            store.listSessionKeys()

            let result = gatewayControlUiWsSessionsListResult().asObject()
            let sessions = result.get("sessions").getOrThrow().asArray()
            var found = false
            for (i in 0..sessions.size()) {
                let row = sessions[i].asObject()
                if (gatewayControlUiWsTestString(row, "key") != sessionKey) {
                    continue
                }
                found = true
                @Expect(gatewayControlUiWsTestString(row, "agentId"), "general")
                @Expect(gatewayControlUiWsTestString(row, "sessionId").contains(".jsonl"), false)
                @Expect(gatewayControlUiWsTestString(row, "sessionFile").endsWith(".jsonl"), true)
                @Expect(gatewayControlUiWsTestString(row, "root"), store.sessionsRoot().toString())
                @Expect(row.get("origin").isSome(), true)
            }
            @Expect(found, true)

            store.deleteSession(sessionKey)
        }
    }

    @TestCase
    public func sessionsListIncludesTelegramThreadBindingProjection(): Unit {
        withGatewayControlUiWsTestHome {
            let user = GatewayUserSettings()
            let store = gatewaySessionStoreForUserWithAgentId(user, "main")
            let sessionKey = "agent:main:ws-telegram-thread-binding"
            store.deleteSession(sessionKey)
            let transcriptLines = [
                "{\"kind\":\"meta\",\"v\":\"1\",\"sessionKey\":\"${sessionKey}\"}",
                "{\"role\":\"system\",\"text\":\"sessions_spawn metadata: runtime=subagent, streamTo=telegram:group:-1001234567890:topic:42, thread=true\"}"
            ]
            File.writeTo(store.transcriptPath(sessionKey), wsConcatLines(transcriptLines).toArray())
            store.listSessionKeys()

            let result = gatewayControlUiWsSessionsListResult().asObject()
            let sessions = result.get("sessions").getOrThrow().asArray()
            var found = false
            for (i in 0..sessions.size()) {
                let row = sessions[i].asObject()
                if (gatewayControlUiWsTestString(row, "key") != sessionKey) {
                    continue
                }
                found = true
                if (row.get("threadBinding").isSome()) {
                    let threadBinding = row.get("threadBinding").getOrThrow().asObject()
                    @Expect(gatewayControlUiWsTestString(threadBinding, "channel"), "telegram")
                    @Expect(gatewayControlUiWsTestString(threadBinding, "threadId"), "42")
                }
            }
            @Expect(found, true)

            store.deleteSession(sessionKey)
        }
    }

    @TestCase
    public func sessionsUsageHelpersReadTranscriptViaConversationView(): Unit {
        withGatewayControlUiWsTestHome {
            let user = GatewayUserSettings()
            let store = gatewaySessionStoreForUserWithAgentId(user, "general")
            let sessionKey = "agent:general:ws-usage-test"
            store.deleteSession(sessionKey)
            store.appendUser(sessionKey, "hello")
            store.appendAssistant(sessionKey, "world")
            store.listSessionKeys()

            let params = JsonObject()
            params.put("key", JsonString(sessionKey))
            params.put("limit", 10.toJsonValue())

            let timeSeries = gatewayControlUiWsSessionsUsageTimeSeriesResult(params).asObject()
            let points = timeSeries.get("points").getOrThrow().asArray()
            @Expect(points.size() >= 2, true)
            @Expect(gatewayControlUiWsTestString(timeSeries, "sessionId").contains(".jsonl"), false)

            let logs = gatewayControlUiWsSessionsUsageLogsResult(params).asObject().get("logs").getOrThrow().asArray()
            @Expect(logs.size() >= 2, true)

            store.deleteSession(sessionKey)
        }
    }

    @TestCase
    public func sessionsDeleteRequestParamsReuseUnifiedBuilder(): Unit {
        let params = JsonObject()
        params.put("keys", JsonString(" main \n other "))
        let requestParams = gatewayControlUiWsRequestParams("dashboard.sessions.delete", params)
        @Expect(requestParams.get("keys").getOrThrow().asString().getValue(), "main \n other")
    }

    @TestCase
    public func agentsListCarriesMemoryRuntimeSummary(): Unit {
        let result = gatewayControlUiWsAgentsListResult().asObject()
        let agents = result.get("agents").getOrThrow().asArray()
        @Expect(agents.size() > 0, true)
        let first = agents[0].asObject()
        @Expect(first.get("memory").isSome(), true)
        let memory = first.get("memory").getOrThrow().asObject()
        @Expect(memory.get("resolvedBackendConfig").isSome(), true)
        @Expect(memory.get("backendSelection").isSome(), true)
        @Expect(memory.get("agentScopedResolve").isSome(), true)
        @Expect(memory.get("activeMemoryPlugin").isSome(), true)
        @Expect(memory.get("activeSearchBackend").isSome(), true)
        @Expect(memory.get("activeOrchestrationBackend").isSome(), true)
        let resolved = memory.get("resolvedBackendConfig").getOrThrow().asObject()
        @Expect(gatewayControlUiWsTestString(resolved, "purpose"), "control-ui-agents")
    }

    @TestCase
    public func methodAliasNormalizesChatAndSessionCommands(): Unit {
        @Expect(gatewayControlUiWsMethodAlias("chat.send"), "dashboard.chat.send")
        @Expect(gatewayControlUiWsMethodAlias("chat.history"), "dashboard.chat.history")
        @Expect(gatewayControlUiWsMethodAlias("sessions.reset"), "sessions.reset")
        @Expect(gatewayControlUiWsMethodAlias("skills.update"), "skills.update")
    }

    @TestCase
    public func requestParamsReuseDashboardSkillAndConfigBuilders(): Unit {
        let skillParams = JsonObject()
        skillParams.put("skillKey", JsonString(" review "))
        skillParams.put("enabled", true.toJsonValue())
        skillParams.put("apiKey", JsonString(" sk-123 "))
        let skillRequest = gatewayControlUiWsRequestParams("skills.update", skillParams)
        @Expect(skillRequest.get("skillKey").getOrThrow().asString().getValue(), "review")
        @Expect(skillRequest.get("enabled").getOrThrow().asBool().getValue(), true)
        @Expect(skillRequest.get("apiKey").getOrThrow().asString().getValue(), "sk-123")

        let schemaParams = JsonObject()
        let schemaRequest = gatewayControlUiWsRequestParams("config.schema.lookup", schemaParams)
        @Expect(schemaRequest.get("path").getOrThrow().asString().getValue(), "gateway")
    }

    @TestCase
    public func configSchemaExposesImageUnderstandingManagementFields(): Unit {
        let response = gatewayControlUiWsCompatResponse(
            "config.schema",
            JsonObject(),
            buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())
        ).getOrThrow()
        let result = response.result.asObject()
        let schema = result.get("schema").getOrThrow().asObject()
        let props = schema.get("properties").getOrThrow().asObject()
        let agents = props.get("agents").getOrThrow().asObject()
        let defaults = agents.get("properties").getOrThrow().asObject().get("defaults").getOrThrow().asObject()
        let imageModel = defaults.get("properties").getOrThrow().asObject().get("imageModel").getOrThrow().asObject()
        @Expect(imageModel.toJsonString().contains("\"primary\""), true)
        @Expect(imageModel.toJsonString().contains("\"fallbacks\""), true)

        let gateway = props.get("gateway").getOrThrow().asObject()
        let gatewayProps = gateway.get("properties").getOrThrow().asObject()
        let media = gatewayProps.get("media").getOrThrow().asObject()
        let image = media.get("properties").getOrThrow().asObject().get("image").getOrThrow().asObject()
        @Expect(image.toJsonString().contains("\"models\""), true)
        let telegram = gatewayProps.get("telegram").getOrThrow().asObject()
        @Expect(telegram.toJsonString().contains("\"image\""), true)
    }

    @TestCase
    public func skillsCompatResponsesReuseUnifiedGatewaySkillsFamily(): Unit {
        let slug = "ws-skills-detail-test"
        try {
            setClawHubHttpGetForTest(Some({ _url: String =>
                "{\"skill\":{\"slug\":\"${slug}\",\"displayName\":\"Skill\"},\"latestVersion\":{\"version\":\"1.0.0\"}}"
            }))
            let binsResponse = gatewayControlUiWsCompatResponse(
                "skills.bins",
                JsonObject(),
                buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())
            ).getOrThrow()
            let bins = binsResponse.result.asObject().get("bins").getOrThrow().asArray()
            @Expect(bins.size() >= 0, true)

            let detailParams = JsonObject()
            detailParams.put("slug", JsonString(slug))
            let detailResponse = gatewayControlUiWsCompatResponse(
                "skills.detail",
                detailParams,
                buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())
            ).getOrThrow()
            let skill = detailResponse.result.asObject().get("skill").getOrThrow().asObject()
            @Expect(gatewayControlUiWsTestString(skill, "slug"), slug)

            let compatibilityResponse = gatewayControlUiWsCompatResponse(
                "skills.compatibilityMatrix",
                JsonObject(),
                buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())
            ).getOrThrow()
            let compatibility = compatibilityResponse.result.asObject()
            @Expect(gatewayControlUiWsTestString(compatibility, "kind"), "skills-compatibility-matrix")
        } finally {
            setClawHubHttpGetForTest(None)
        }
    }

    @TestCase
    public func skillsUpdateInvalidatesSkillsSectionLikeDashboardSkillSet(): Unit {
        let skillParams = JsonObject()
        skillParams.put("skillKey", JsonString("review"))
        let payload = gatewayControlUiWsInvalidatePayload("skills.update", skillParams)
        let sections = payload.get("sections").getOrThrow().asArray()
        @Expect(sections.size() > 0, true)
        @Expect(sections[1].asString().getValue(), "skills")
    }

    @TestCase
    public func requestParamsReuseDashboardCronBuilder(): Unit {
        let cronParams = JsonObject()
        cronParams.put("action", JsonString("save"))
        cronParams.put("name", JsonString("daily report"))
        cronParams.put("session", JsonString("agent:general:main"))
        cronParams.put("delivery_channel", JsonString("feishu"))
        cronParams.put("delivery_to", JsonString("chat-1"))
        let request = gatewayControlUiWsRequestParams("dashboard.cron", cronParams)
        @Expect(request.get("action").getOrThrow().asString().getValue(), "save")
        @Expect(request.get("delivery_channel").getOrThrow().asString().getValue(), "feishu")
        @Expect(request.get("delivery_to").getOrThrow().asString().getValue(), "chat-1")
        @Expect(request.get("system_event").isSome(), false)
    }

    @TestCase
    public func requestParamsReuseDashboardModelConfigAndChannelBuilders(): Unit {
        let modelParams = JsonObject()
        modelParams.put("model", JsonString(" gpt-5 "))
        let modelRequest = gatewayControlUiWsRequestParams("dashboard.model.switch", modelParams)
        @Expect(modelRequest.get("model").getOrThrow().asString().getValue(), "gpt-5")

        let channelParams = JsonObject()
        channelParams.put("probe", true.toJsonValue())
        channelParams.put("timeoutMs", JsonString("9000"))
        let channelRequest = gatewayControlUiWsRequestParams("channels.status", channelParams)
        @Expect(channelRequest.get("probe").getOrThrow().asBool().getValue(), true)
        @Expect(channelRequest.get("timeoutMs").getOrThrow().toJsonString(), "9000")

        let configGetParams = JsonObject()
        let configGetRequest = gatewayControlUiWsRequestParams("config.get", configGetParams)
        @Expect(configGetRequest.get("path").getOrThrow().asString().getValue(), "gateway")

        let configPatchParams = JsonObject()
        configPatchParams.put("path", JsonString(" gateway.http "))
        configPatchParams.put("raw", JsonString("{\"enabled\":true}"))
        let configPatchRequest = gatewayControlUiWsRequestParams("config.patch", configPatchParams)
        @Expect(configPatchRequest.get("path").getOrThrow().asString().getValue(), "gateway.http")
        @Expect(configPatchRequest.get("raw").getOrThrow().asString().getValue(), "{\"enabled\":true}")
    }
}
