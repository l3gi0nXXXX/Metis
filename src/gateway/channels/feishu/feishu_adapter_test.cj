package metis.gateway.channels.feishu

import metis.core.renderGatewayEditText
import metis.gateway.core.{gatewayPolicyFilteredChatToolNamesForTurnContext, gatewayPolicyFilteredSystemPromptForTurnContext, gatewayResolveSessionContextWithAgentRoute}
import metis.gateway.model.{ChannelPolicyConfig, ChannelType, FeishuConfig, FeishuMediaConfig, InboundMessage, OutboundMessage}
import metis.gateway.session.gatewaySessionRequestFromInbound
import std.collection.ArrayList
import std.core.Duration
import std.fs.{File, Path, exists, remove}
import std.sync.Mutex
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject, JsonString, JsonValue}

class FeishuQueueProbe {
    private let lock = Mutex()
    private var sameThreadActive = 0
    private var sameThreadOverlap = false
    private var otherThreadObservedParallel = false

    func runSameThreadTask(durationMs: Int64): Unit {
        synchronized(this.lock) {
            this.sameThreadActive += 1
            if (this.sameThreadActive > 1) {
                this.sameThreadOverlap = true
            }
        }
        sleep(Duration.millisecond * durationMs)
        synchronized(this.lock) {
            this.sameThreadActive -= 1
        }
    }

    func runOtherThreadTask(): Unit {
        synchronized(this.lock) {
            if (this.sameThreadActive > 0) {
                this.otherThreadObservedParallel = true
            }
        }
    }

    func sameOverlap(): Bool {
        synchronized(this.lock) {
            this.sameThreadOverlap
        }
    }

    func otherObservedParallel(): Bool {
        synchronized(this.lock) {
            this.otherThreadObservedParallel
        }
    }
}

@Test
public class FeishuAdapterTest {
    private func jsonObjectField(obj: JsonObject, key: String): JsonObject {
        try {
            obj.get(key).getOrThrow().asObject()
        } catch (_: Exception) {
            JsonObject()
        }
    }

    private func jsonStringField(obj: JsonObject, key: String): String {
        try {
            obj.get(key).getOrThrow().asString().getValue()
        } catch (_: Exception) {
            ""
        }
    }

    private func webhookPayload(
        messageId: String,
        chatId: String,
        senderId: String,
        text: String,
        chatType!: String = "group",
        messageType!: String = "text",
        rootId!: String = "",
        threadId!: String = "",
        headerAccountId!: String = "",
        appId!: String = "",
        createTime!: String = "",
        mentions!: String = ""
    ): String {
        let headerParts = ArrayList<String>()
        if (!headerAccountId.isEmpty()) {
            headerParts.add("\"account_id\":\"${headerAccountId}\"")
        }
        if (!appId.isEmpty()) {
            headerParts.add("\"app_id\":\"${appId}\"")
        }
        let headerExtra = if (headerParts.isEmpty()) { "" } else { "," + String.join(headerParts.toArray(), delimiter: ",") }
        let mentionField = if (!mentions.isEmpty()) { ",\"mentions\":${mentions}" } else { "" }
        let createTimeField = if (!createTime.isEmpty()) { ",\"create_time\":\"${createTime}\"" } else { "" }
        "{" +
            "\"header\":{\"event_type\":\"im.message.receive_v1\"${headerExtra}}," +
            "\"event\":{" +
            "\"sender\":{\"sender_id\":{\"open_id\":\"${senderId}\"}}," +
            "\"message\":{" +
            "\"message_id\":\"${messageId}\"," +
            "\"chat_id\":\"${chatId}\"," +
            "\"chat_type\":\"${chatType}\"," +
            "\"message_type\":\"${messageType}\"," +
            "\"content\":\"${text}\"," +
            "\"root_id\":\"${rootId}\"," +
            "\"thread_id\":\"${threadId}\"" +
            createTimeField +
            mentionField +
            "}" +
            "}" +
            "}"
    }

    private func cardActionPayload(action: String, accountId!: String = "tenant-a"): String {
        "{" +
            "\"header\":{\"event_type\":\"card.action.trigger\",\"account_id\":\"${accountId}\"}," +
            "\"event\":{" +
            "\"operator\":{\"open_id\":\"ou_operator\"}," +
            "\"context\":{\"open_message_id\":\"om_card\",\"open_chat_id\":\"oc_card\"}," +
            "\"action\":{\"value\":{\"action\":\"${action}\",\"nonce\":\"n-1\"}}" +
            "}" +
            "}"
    }

    private func reactionPayload(accountId!: String = "tenant-a", actionTime!: String = ""): String {
        let effectiveActionTime = if (actionTime.trimAscii().isEmpty()) {
            DateTime.now().toUnixTimeStamp().toMilliseconds().toString()
        } else {
            actionTime.trimAscii()
        }
        "{" +
            "\"header\":{\"event_type\":\"im.message.reaction.created_v1\",\"account_id\":\"${accountId}\"}," +
            "\"event\":{" +
            "\"message_id\":\"om_reacted\"," +
            "\"chat_id\":\"oc_react\"," +
            "\"chat_type\":\"group\"," +
            "\"thread_id\":\"omt_react\"," +
            "\"reaction_type\":{\"emoji_type\":\"THUMBSUP\"}," +
            "\"user_id\":{\"open_id\":\"ou_reactor\"}," +
            "\"action_time\":\"${effectiveActionTime}\"" +
            "}" +
            "}"
    }

    private func botMembershipPayload(eventType: String, accountId!: String = "tenant-a"): String {
        "{" +
            "\"header\":{\"event_type\":\"${eventType}\",\"account_id\":\"${accountId}\"}," +
            "\"event\":{\"chat_id\":\"oc_bot\",\"operator_id\":{\"open_id\":\"ou_owner\"}}" +
            "}"
    }

    private func vcInvitedPayload(accountId!: String = "tenant-a"): String {
        "{" +
            "\"header\":{\"event_type\":\"vc.meeting.invited_v1\",\"account_id\":\"${accountId}\"}," +
            "\"event\":{\"event_id\":\"ev_vc_1\",\"meeting\":{\"meeting_no\":\"123456\"},\"operator_id\":{\"open_id\":\"ou_inviter\"}}" +
            "}"
    }

    private func bitableFieldChangedPayload(accountId!: String = "tenant-a"): String {
        "{" +
            "\"header\":{\"event_type\":\"bitable.field.changed_v1\",\"account_id\":\"${accountId}\"}," +
            "\"event\":{\"app_token\":\"bascn_1\",\"table_id\":\"tbl_1\",\"field_id\":\"fld_1\",\"operator_id\":{\"open_id\":\"ou_editor\"}}" +
            "}"
    }

    private func driveCommentPayload(accountId!: String = "tenant-a"): String {
        "{" +
            "\"header\":{\"event_type\":\"drive.file.comment.created_v1\",\"account_id\":\"${accountId}\"}," +
            "\"event\":{" +
            "\"comment_id\":\"comment_1\"," +
            "\"reply_id\":\"reply_1\"," +
            "\"file_token\":\"doccn_1\"," +
            "\"file_type\":\"docx\"," +
            "\"is_mention\":true," +
            "\"user_id\":{\"open_id\":\"ou_commenter\"}," +
            "\"content\":\"please review\"" +
            "}" +
            "}"
    }

    private func fixtureString(obj: JsonObject, key: String): String {
        match (obj.get(key)) {
            case Some(v) => try { v.asString().getValue() } catch (_e: Exception) { "" }
            case None => ""
        }
    }

    private func fixtureBool(obj: JsonObject, key: String, fallback: Bool): Bool {
        match (obj.get(key)) {
            case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { fallback }
            case None => fallback
        }
    }

    private func expectFixtureInbound(inbound: InboundMessage, expected: JsonObject): Unit {
        let accountId = this.fixtureString(expected, "accountId")
        if (!accountId.isEmpty()) {
            @Expect(inbound.accountId, accountId)
            @Expect(inbound.mediaContext.get("accountId").getOrThrow().asString().getValue(), accountId)
        }
        let peerId = this.fixtureString(expected, "peerId")
        if (!peerId.isEmpty()) {
            @Expect(inbound.peerId, peerId)
            @Expect(inbound.mediaContext.get("peerId").getOrThrow().asString().getValue(), peerId)
        }
        let messageId = this.fixtureString(expected, "messageId")
        if (!messageId.isEmpty()) {
            @Expect(inbound.messageId, messageId)
        }
        let mediaMessageId = this.fixtureString(expected, "mediaMessageId")
        if (!mediaMessageId.isEmpty()) {
            @Expect(inbound.mediaContext.get("messageId").getOrThrow().asString().getValue(), mediaMessageId)
        }
        let threadId = this.fixtureString(expected, "threadId")
        if (!threadId.isEmpty()) {
            @Expect(inbound.threadId.getOrThrow(), threadId)
        } else {
            @Expect(inbound.threadId.isNone(), true)
        }
        let kind = this.fixtureString(expected, "systemEventKind")
        if (kind.isEmpty()) {
            @Expect(inbound.systemEvent, false)
        } else {
            @Expect(inbound.systemEvent, true)
            @Expect(inbound.systemEventKind, kind)
        }
        let mediaKind = this.fixtureString(expected, "mediaKind")
        if (!mediaKind.isEmpty()) {
            let records = inbound.mediaContext.get("records").getOrThrow().asArray()
            @Expect(records.size(), 1)
            @Expect(records[0].asObject().get("mediaKind").getOrThrow().asString().getValue(), mediaKind)
        }
    }

    @TestCase
    public func accountResolverMergesDefaultAndAccountOverridesWithRedaction(): Unit {
        let accounts = JsonObject()
        let tenant = JsonObject()
        tenant.put("enabled", JsonBool(false))
        tenant.put("appId", JsonString("tenant-app"))
        tenant.put("receiveMode", JsonString("webhook"))
        tenant.put("groupPolicy", JsonString("open"))
        tenant.put("requireMention", JsonBool(false))
        let accountGroups = JsonObject()
        accountGroups.put("oc_account", JsonObject())
        tenant.put("groups", accountGroups)
        accounts.put("tenant-a", tenant)

        let baseGroups = JsonObject()
        baseGroups.put("oc_base", JsonObject())
        let config = FeishuConfig(
            enabled: true,
            defaultAccount: "tenant-a",
            appId: "base-app",
            appSecret: "base-secret-never-visible",
            accounts: Some(accounts),
            receiveMode: "long_connect",
            groups: Some(baseGroups),
            groupPolicy: "allowlist",
            requireMention: true
        )

        let resolved = gatewayFeishuResolveAccount(config, "tenant-a")
        @Expect(resolved.accountId, "tenant-a")
        @Expect(resolved.explicitAccount, true)
        @Expect(resolved.config.enabled, false)
        @Expect(resolved.config.appId, "tenant-app")
        @Expect(resolved.config.appSecret, "base-secret-never-visible")
        @Expect(resolved.config.receiveMode, "webhook")
        @Expect(resolved.config.groupPolicy, "open")
        @Expect(resolved.config.requireMention, false)
        @Expect(resolved.config.groups.getOrThrow().getFields().contains("oc_account"), true)

        let descriptions = gatewayFeishuDescribeAccounts(config)
        let raw = descriptions.toJsonString()
        @Expect(raw.contains("tenant-a"), true)
        @Expect(raw.contains("base-secret-never-visible"), false)
        @Expect(raw.contains("tenant-app"), false)
        let firstDescription = descriptions.get("accounts").getOrThrow().asArray().getItems()[0].asObject()
        @Expect(firstDescription.get("credentialSource").getOrThrow().asString().getValue(), "mixed")
        let credentialSources = firstDescription.get("credentialSources").getOrThrow().asObject()
        @Expect(credentialSources.get("appId").getOrThrow().asString().getValue(), "account")
        @Expect(credentialSources.get("appSecret").getOrThrow().asString().getValue(), "top-level")
    }

    @TestCase
    public func accountResolverDeepMergesSupportedNestedGroupOverrides(): Unit {
        let baseTeam = JsonObject()
        baseTeam.put("requireMention", JsonBool(true))
        let baseTools = JsonObject()
        baseTools.put("deny", JsonArray([JsonString("feishu_drive_file")]))
        baseTeam.put("tools", baseTools)
        let baseWildcard = JsonObject()
        baseWildcard.put("allowBots", JsonBool(false))
        let baseGroups = JsonObject()
        baseGroups.put("oc_team", baseTeam)
        baseGroups.put("*", baseWildcard)

        let accountTeam = JsonObject()
        accountTeam.put("systemPrompt", JsonString("tenant-a group prompt"))
        let accountTools = JsonObject()
        accountTools.put("allow", JsonArray([JsonString("feishu_fetch_doc")]))
        accountTeam.put("tools", accountTools)
        let accountOnly = JsonObject()
        accountOnly.put("requireMention", JsonBool(false))
        let accountGroups = JsonObject()
        accountGroups.put("oc_team", accountTeam)
        accountGroups.put("oc_account_only", accountOnly)
        let tenant = JsonObject()
        tenant.put("groups", accountGroups)
        let accounts = JsonObject()
        accounts.put("tenant-a", tenant)

        let config = FeishuConfig(
            enabled: true,
            defaultAccount: "tenant-a",
            accounts: Some(accounts),
            groups: Some(baseGroups)
        )

        let resolvedGroups = gatewayFeishuResolveAccount(config, "tenant-a").config.groups.getOrThrow()
        @Expect(resolvedGroups.getFields().contains("oc_team"), true)
        @Expect(resolvedGroups.getFields().contains("oc_account_only"), true)
        @Expect(resolvedGroups.getFields().contains("*"), true)
        let mergedTeam = resolvedGroups.get("oc_team").getOrThrow().asObject()
        @Expect(mergedTeam.get("requireMention").getOrThrow().asBool().getValue(), true)
        @Expect(mergedTeam.get("systemPrompt").getOrThrow().asString().getValue(), "tenant-a group prompt")
        let mergedTools = mergedTeam.get("tools").getOrThrow().asObject()
        @Expect(mergedTools.get("allow").getOrThrow().asArray().size(), 1)
        @Expect(mergedTools.get("deny").getOrThrow().asArray().size(), 1)
    }

    @TestCase
    public func accountResolverReportsUnsupportedAccountFieldsAsIgnoredDiagnostics(): Unit {
        let tenant = JsonObject()
        tenant.put("connectionMode", JsonString("websocket"))
        tenant.put("dmPolicy", JsonString("open"))
        tenant.put("historyLimit", JsonInt(20))
        tenant.put("replyMode", JsonString("card"))
        tenant.put("footer", JsonObject())
        tenant.put("uat", JsonObject())
        tenant.put("dedup", JsonObject())
        tenant.put("reactionNotifications", JsonString("all"))
        tenant.put("markdown", JsonObject())
        tenant.put("capabilities", JsonObject())
        let group = JsonObject()
        group.put("respondToMentionAll", JsonBool(true))
        let accountGroups = JsonObject()
        accountGroups.put("oc_team", group)
        tenant.put("groups", accountGroups)
        let accounts = JsonObject()
        accounts.put("tenant-a", tenant)

        let config = FeishuConfig(
            enabled: true,
            defaultAccount: "tenant-a",
            appId: "base-app",
            appSecret: "base-secret-never-visible",
            accounts: Some(accounts)
        )

        let descriptions = gatewayFeishuDescribeAccounts(config)
        let raw = descriptions.toJsonString()
        @Expect(raw.contains("base-secret-never-visible"), false)
        @Expect(raw.contains("unsupportedFields"), true)
        @Expect(raw.contains("ignoredFields"), true)
        @Expect(raw.contains("accounts.tenant-a.connectionMode"), true)
        @Expect(raw.contains("accounts.tenant-a.historyLimit"), true)
        @Expect(raw.contains("accounts.tenant-a.replyMode"), true)
        @Expect(raw.contains("accounts.tenant-a.footer"), true)
        @Expect(raw.contains("accounts.tenant-a.uat"), true)
        @Expect(raw.contains("accounts.tenant-a.dedup"), true)
        @Expect(raw.contains("accounts.tenant-a.reactionNotifications"), true)
        @Expect(raw.contains("accounts.tenant-a.markdown"), true)
        @Expect(raw.contains("accounts.tenant-a.capabilities"), true)
        @Expect(raw.contains("accounts.tenant-a.groups.oc_team.respondToMentionAll"), true)
        let unsupportedRows = descriptions.get("unsupportedFields").getOrThrow().asArray().toJsonString()
        let ignoredRows = descriptions.get("ignoredFields").getOrThrow().asArray().toJsonString()
        @Expect(unsupportedRows.contains("status"), true)
        @Expect(unsupportedRows.contains("unsupported"), true)
        @Expect(ignoredRows.contains("status"), true)
        @Expect(ignoredRows.contains("ignored"), true)
    }

    @TestCase
    public func accountDescriptionsExposeRuntimeStatusForEveryConfiguredAccount(): Unit {
        let tenantA = JsonObject()
        tenantA.put("appId", JsonString("tenant-a-app"))
        tenantA.put("appSecret", JsonString("tenant-a-secret-never-visible"))
        let tenantB = JsonObject()
        tenantB.put("enabled", JsonBool(false))
        let accounts = JsonObject()
        accounts.put("tenant-a", tenantA)
        accounts.put("tenant-b", tenantB)
        let config = FeishuConfig(
            enabled: true,
            defaultAccount: "tenant-a",
            appId: "top-app",
            appSecret: "top-secret-never-visible",
            accounts: Some(accounts)
        )
        let runtimeAccounts = JsonArray([])
        let running = JsonObject()
        running.put("accountId", JsonString("tenant-a"))
        running.put("running", JsonBool(true))
        running.put("lastError", JsonString(""))
        runtimeAccounts.add(running)
        let failed = JsonObject()
        failed.put("accountId", JsonString("tenant-b"))
        failed.put("running", JsonBool(false))
        failed.put("lastError", JsonString("Authorization: Bearer token-never-visible"))
        runtimeAccounts.add(failed)
        let runtime = JsonObject()
        runtime.put("accounts", runtimeAccounts)

        let descriptions = gatewayFeishuDescribeAccounts(config, runtime: runtime)
        let raw = descriptions.toJsonString()

        @Expect(raw.contains("top-secret-never-visible"), false)
        @Expect(raw.contains("tenant-a-secret-never-visible"), false)
        @Expect(raw.contains("token-never-visible"), false)
        @Expect(descriptions.get("defaultAccountId").getOrThrow().asString().getValue(), "tenant-a")
        let rows = descriptions.get("accounts").getOrThrow().asArray()
        @Expect(rows.size(), 2)
        let tenantARow = rows[0].asObject()
        let tenantBRow = rows[1].asObject()
        @Expect(tenantARow.get("accountId").getOrThrow().asString().getValue(), "tenant-a")
        @Expect(tenantARow.get("defaultAccount").getOrThrow().asBool().getValue(), true)
        @Expect(tenantARow.get("configured").getOrThrow().asBool().getValue(), true)
        @Expect(tenantARow.get("running").getOrThrow().asBool().getValue(), true)
        @Expect(tenantARow.get("credentialSource").getOrThrow().asString().getValue(), "account")
        @Expect(tenantBRow.get("accountId").getOrThrow().asString().getValue(), "tenant-b")
        @Expect(tenantBRow.get("enabled").getOrThrow().asBool().getValue(), false)
        @Expect(tenantBRow.get("configured").getOrThrow().asBool().getValue(), true)
        @Expect(tenantBRow.get("running").getOrThrow().asBool().getValue(), false)
        @Expect(tenantBRow.get("lastError").getOrThrow().asString().getValue(), "[redacted]")
    }

    @TestCase
    public func accountDescriptionsExposeRouteAndLiveReadinessDiagnostics(): Unit {
        let tenantA = JsonObject()
        tenantA.put("appId", JsonString("tenant-a-app"))
        tenantA.put("appSecret", JsonString("tenant-a-secret-never-visible"))
        tenantA.put("threadSession", JsonBool(true))
        tenantA.put("replyInThread", JsonString("enabled"))
        let tenantB = JsonObject()
        tenantB.put("enabled", JsonBool(false))
        let accounts = JsonObject()
        accounts.put("tenant-a", tenantA)
        accounts.put("tenant-b", tenantB)
        let config = FeishuConfig(
            enabled: true,
            defaultAccount: "tenant-a",
            appId: "top-app",
            appSecret: "top-secret-never-visible",
            accounts: Some(accounts),
            groupPolicy: "allowlist",
            requireMention: true
        )

        let descriptions = gatewayFeishuDescribeAccounts(config)
        let routeDiagnostics = descriptions.get("routeDiagnostics").getOrThrow().asObject()
        @Expect(routeDiagnostics.get("status").getOrThrow().asString().getValue(), "multi_account_ready")
        @Expect(routeDiagnostics.get("bindingMatchDimensions").getOrThrow().asArray()[1].asString().getValue(), "accountId")
        @Expect(routeDiagnostics.get("manualAcceptance").getOrThrow().asArray()[0].asString().getValue(), "M15")

        let rows = descriptions.get("accounts").getOrThrow().asArray()
        let tenantARoute = rows[0].asObject().get("routeDiagnostic").getOrThrow().asObject()
        @Expect(tenantARoute.get("channel").getOrThrow().asString().getValue(), "feishu")
        @Expect(tenantARoute.get("accountId").getOrThrow().asString().getValue(), "tenant-a")
        @Expect(tenantARoute.get("bindingStatus").getOrThrow().asString().getValue(), "ready_for_binding")
        @Expect(tenantARoute.get("threadSession").getOrThrow().asBool().getValue(), true)
        @Expect(tenantARoute.get("replyInThread").getOrThrow().asString().getValue(), "enabled")

        let tenantBLive = rows[1].asObject().get("liveReadiness").getOrThrow().asObject()
        @Expect(tenantBLive.get("state").getOrThrow().asString().getValue(), "disabled")
        @Expect(tenantBLive.get("nextStep").getOrThrow().asString().getValue(), "enable_account_or_remove_binding")
        @Expect(descriptions.toJsonString().contains("top-secret-never-visible"), false)
        @Expect(descriptions.toJsonString().contains("tenant-a-secret-never-visible"), false)
    }

    @TestCase
    public func disabledAccountOverrideDoesNotRunAdapterTransport(): Unit {
        let accounts = JsonObject()
        let disabled = JsonObject()
        disabled.put("enabled", JsonBool(false))
        accounts.put("tenant-off", disabled)
        let adapter = FeishuAdapter(
            config: FeishuConfig(enabled: true, accounts: Some(accounts)),
            accountId: "tenant-off"
        )
        adapter.start()
        adapter.simulateIncomingText("om_disabled", "oc_group", "ou_1", "hello")
        @Expect(adapter.pullInbound().size, 0)
    }

    @TestCase
    public func adapterUsesAccountScopedGroupPolicyForInboundGate(): Unit {
        let accounts = JsonObject()
        let tenant = JsonObject()
        tenant.put("groupPolicy", JsonString("open"))
        tenant.put("requireMention", JsonBool(false))
        tenant.put("botOpenId", JsonString("bot-open"))
        accounts.put("tenant-a", tenant)
        let adapter = FeishuAdapter(
            config: FeishuConfig(
                enabled: true,
                accounts: Some(accounts),
                groupPolicy: "allowlist",
                requireMention: true
            ),
            accountId: "tenant-a"
        )
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_account_gate",
                "oc_not_in_base_allowlist",
                "ou_1",
                "{\\\"text\\\":\\\"plain group message\\\"}"
            )
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        let gate = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuGate").getOrThrow().asObject()
        @Expect(gate.get("triggerAgent").getOrThrow().asBool().getValue(), true)
        @Expect(gate.get("reason").getOrThrow().asString().getValue(), "accepted")
    }

    @TestCase
    public func sameChatIdUsesIsolatedAccountScopedGroupPolicies(): Unit {
        let tenantAGroup = JsonObject()
        tenantAGroup.put("requireMention", JsonBool(false))
        let tenantATools = JsonObject()
        tenantATools.put("allow", JsonArray([JsonString("feishu_fetch_doc")]))
        tenantAGroup.put("tools", tenantATools)
        let tenantAGroups = JsonObject()
        tenantAGroups.put("oc_shared", tenantAGroup)
        let tenantA = JsonObject()
        tenantA.put("groups", tenantAGroups)

        let tenantBGroup = JsonObject()
        tenantBGroup.put("enabled", JsonBool(false))
        tenantBGroup.put("systemPrompt", JsonString("tenant-b-disabled-prompt"))
        let tenantBGroups = JsonObject()
        tenantBGroups.put("oc_shared", tenantBGroup)
        let tenantB = JsonObject()
        tenantB.put("groups", tenantBGroups)

        let accounts = JsonObject()
        accounts.put("tenant-a", tenantA)
        accounts.put("tenant-b", tenantB)

        let adapter = FeishuAdapter(
            config: FeishuConfig(
                enabled: true,
                accounts: Some(accounts),
                groupPolicy: "allowlist",
                requireMention: true
            )
        )
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_tenant_a",
                "oc_shared",
                "ou_1",
                "{\\\"text\\\":\\\"plain group message\\\"}",
                headerAccountId: "tenant-a"
            )
        ).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_tenant_b",
                "oc_shared",
                "ou_2",
                "{\\\"text\\\":\\\"plain group message\\\"}",
                headerAccountId: "tenant-b"
            )
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 2)
        let tenantAGate = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuGate").getOrThrow().asObject()
        let tenantBGate = inbound[1].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuGate").getOrThrow().asObject()
        @Expect(inbound[0].accountId, "tenant-a")
        @Expect(inbound[1].accountId, "tenant-b")
        @Expect(tenantAGate.get("triggerAgent").getOrThrow().asBool().getValue(), true)
        @Expect(tenantAGate.get("reason").getOrThrow().asString().getValue(), "accepted")
        @Expect(tenantBGate.get("triggerAgent").getOrThrow().asBool().getValue(), false)
        @Expect(tenantBGate.get("reason").getOrThrow().asString().getValue(), "group_disabled")
        let tenantARoute = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("imRoute").getOrThrow().asObject()
        let tenantBRoute = inbound[1].mediaContext.get("context").getOrThrow().asObject()
            .get("imRoute").getOrThrow().asObject()
        @Expect(tenantARoute.get("accountId").getOrThrow().asString().getValue(), "tenant-a")
        @Expect(tenantBRoute.get("accountId").getOrThrow().asString().getValue(), "tenant-b")
        @Expect(tenantARoute.get("groupPolicy").getOrThrow().asObject().toJsonString().contains("feishu_fetch_doc"), true)
        @Expect(tenantBRoute.get("groupPolicy").getOrThrow().asObject().toJsonString().contains("tenant-b-disabled-prompt"), true)
    }

    @TestCase
    public func multiAccountSnakeCasePolicyAllowlistAndThreadSessionAreAccountScoped(): Unit {
        let tenantA = JsonObject()
        tenantA.put("group_policy", JsonString("allowlist"))
        tenantA.put("group_allow_from", JsonArray([JsonString("oc_shared")]))
        tenantA.put("require_mention", JsonBool(false))
        tenantA.put("thread_session", JsonBool(true))

        let tenantB = JsonObject()
        tenantB.put("group_policy", JsonString("allowlist"))
        tenantB.put("group_allow_from", JsonArray([]))
        tenantB.put("require_mention", JsonBool(false))
        tenantB.put("thread_session", JsonBool(false))

        let accounts = JsonObject()
        accounts.put("tenant-a", tenantA)
        accounts.put("tenant-b", tenantB)

        let client = FeishuFakeApiClient()
        client.setThreadCapable("oc_shared", true)
        let adapter = FeishuAdapter(
            config: FeishuConfig(
                enabled: true,
                accounts: Some(accounts),
                groupPolicy: "allowlist",
                requireMention: true,
                threadSession: false
            ),
            apiClient: client
        )
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_tenant_a_policy",
                "oc_shared",
                "ou_1",
                "{\\\"text\\\":\\\"plain topic message\\\"}",
                threadId: "omt_a",
                headerAccountId: "tenant-a"
            )
        ).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_tenant_b_policy",
                "oc_shared",
                "ou_2",
                "{\\\"text\\\":\\\"plain topic message\\\"}",
                threadId: "omt_b",
                headerAccountId: "tenant-b"
            )
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 2)
        let tenantARoute = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("imRoute").getOrThrow().asObject()
        let tenantAGate = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuGate").getOrThrow().asObject()
        let tenantBRoute = inbound[1].mediaContext.get("context").getOrThrow().asObject()
            .get("imRoute").getOrThrow().asObject()
        let tenantBGate = inbound[1].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuGate").getOrThrow().asObject()

        @Expect(inbound[0].accountId, "tenant-a")
        @Expect(inbound[1].accountId, "tenant-b")
        @Expect(tenantAGate.get("triggerAgent").getOrThrow().asBool().getValue(), true)
        @Expect(tenantAGate.get("reason").getOrThrow().asString().getValue(), "accepted")
        @Expect(tenantARoute.get("threadSessionKey").getOrThrow().asString().getValue(), "oc_shared:topic:omt_a")
        @Expect(inbound[0].conversationId.getOrThrow(), "oc_shared:topic:omt_a")
        @Expect(tenantBGate.get("triggerAgent").getOrThrow().asBool().getValue(), false)
        @Expect(tenantBGate.get("reason").getOrThrow().asString().getValue(), "group_not_allowed")
        @Expect(tenantBRoute.get("threadSessionKey").isNone(), true)
        @Expect(client.threadCapabilityChecks("oc_shared"), 1)
    }

    @TestCase
    public func fakeClientRecordsInteractiveCardSendAndPatch(): Unit {
        let client = FeishuFakeApiClient()
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true), apiClient: client)
        adapter.start()
        let card = FeishuInteractiveCard(
            title: "Metis Feishu auth",
            text: "Open the verification URL and enter the user code.",
            actionId: "feishu.auth.start"
        )

        let messageId = adapter.sendInteractiveCardToFeishu("oc_card", card)
        @Expect(messageId, "fake-feishu-card-1")
        @Expect(client.cardSendCount(), 1)
        @Expect(client.sentCard(0).fallbackText().contains("Metis Feishu auth"), true)

        let patched = adapter.patchInteractiveCardInFeishu(messageId, FeishuInteractiveCard(title: "Done", text: "Authorized"))
        @Expect(patched, true)
        @Expect(client.cardPatchCount(), 1)
        @Expect(client.patchedCard(0).fallbackText().contains("Authorized"), true)
    }

    @TestCase
    public func streamingSendWithMessageIdCreatesAndPatchesOneInteractiveCard(): Unit {
        let client = FeishuFakeApiClient()
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true, streaming: "partial"), apiClient: client)
        adapter.start()

        let messageId = adapter.sendWithMessageId(OutboundMessage(
            ChannelType.Feishu,
            "oc_stream",
            "first chunk",
            replyToMessageId: Some("om_source"),
            replyInThread: true,
            accountId: "tenant-a"
        ))
        @Expect(messageId, "fake-feishu-card-1")
        @Expect(client.cardSendCount(), 1)
        @Expect(client.sentCard(0).fallbackText().contains("first chunk"), true)

        let patchedId = adapter.sendWithMessageId(OutboundMessage(
            ChannelType.Feishu,
            "oc_stream",
            renderGatewayEditText("first chunk\nsecond chunk"),
            replyToMessageId: Some(messageId),
            accountId: "tenant-a"
        ))
        @Expect(patchedId, messageId)
        @Expect(client.cardPatchCount(), 1)
        @Expect(client.patchedCard(0).fallbackText().contains("second chunk"), true)
    }

    @TestCase
    public func replyModeTextStaticAndFallbackAreExplicit(): Unit {
        let textClient = FeishuFakeApiClient()
        let textAdapter = FeishuAdapter(config: FeishuConfig(enabled: true, streaming: "text"), apiClient: textClient)
        textAdapter.start()
        let textId = textAdapter.sendWithMessageId(OutboundMessage(ChannelType.Feishu, "oc_text", "plain answer"))
        @Expect(textId, "fake-feishu-text-1")
        @Expect(textClient.textSendCount(), 1)
        @Expect(textClient.cardSendCount(), 0)

        let cardClient = FeishuFakeApiClient()
        let cardAdapter = FeishuAdapter(config: FeishuConfig(enabled: true, streaming: "card"), apiClient: cardClient)
        cardAdapter.start()
        let cardId = cardAdapter.sendWithMessageId(OutboundMessage(ChannelType.Feishu, "oc_card", "card answer"))
        @Expect(cardId, "fake-feishu-card-1")
        @Expect(cardClient.cardSendCount(), 1)
        @Expect(cardClient.cardPatchCount(), 0)

        let fallbackClient = FeishuFakeApiClient()
        fallbackClient.failNextCardSend("rate_limited", error: "card rate limited")
        let fallbackAdapter = FeishuAdapter(config: FeishuConfig(enabled: true, streaming: "card"), apiClient: fallbackClient)
        fallbackAdapter.start()
        let fallbackId = fallbackAdapter.sendWithMessageId(OutboundMessage(ChannelType.Feishu, "oc_fallback", "fallback answer"))
        @Expect(fallbackId, "fake-feishu-text-1")
        @Expect(fallbackClient.cardSendCount(), 1)
        @Expect(fallbackClient.textSendCount(), 1)
    }

    @TestCase
    public func streamingControllerLifecycleIncludesToolFooterAbortAndFallback(): Unit {
        let client = FeishuFakeApiClient()
        let metrics = FeishuReplyFooterMetrics(
            status: "completed",
            elapsedMs: 1234,
            inputTokens: 12,
            outputTokens: 34,
            cacheRead: 3,
            cacheWrite: 4,
            contextTokens: 4096,
            model: "metis-test"
        )
        let controller = FeishuStreamingCardController(
            client,
            accountId: "tenant-a",
            rawPeerId: "oc_stream",
            receiveId: "oc_stream",
            receiveIdType: "chat_id",
            replyToMessageId: Some("om_source"),
            replyInThread: true,
            showToolUse: true
        )

        @Expect(controller.currentPhase(), "idle")
        @Expect(controller.create("first chunk"), "fake-feishu-card-1")
        @Expect(controller.currentPhase(), "streaming")
        @Expect(controller.patchChunk("second chunk"), true)
        @Expect(controller.updateToolPayload("feishu_fetch_doc", "{\"doc\":\"1\"}"), true)
        @Expect(controller.finalize("final answer", footerMetrics: Some(metrics)), true)
        @Expect(controller.currentPhase(), "completed")
        @Expect(client.cardSendCount(), 1)
        @Expect(client.cardPatchCount(), 3)
        @Expect(client.patchedCard(2).fallbackText().contains("Status: completed"), true)
        @Expect(client.patchedCard(2).fallbackText().contains("Elapsed: 1.2s"), true)
        @Expect(client.patchedCard(2).fallbackText().contains("Tokens in: 12"), true)
        @Expect(client.patchedCard(2).fallbackText().contains("Tokens out: 34"), true)
        @Expect(client.patchedCard(2).fallbackText().contains("Cache read: 3"), true)
        @Expect(client.patchedCard(2).fallbackText().contains("Cache write: 4"), true)
        @Expect(client.patchedCard(2).fallbackText().contains("Context: 4096"), true)
        @Expect(client.patchedCard(2).fallbackText().contains("Model: metis-test"), true)

        let abortController = FeishuStreamingCardController(
            client,
            accountId: "tenant-a",
            rawPeerId: "oc_stream",
            receiveId: "oc_stream",
            receiveIdType: "chat_id"
        )
        @Expect(abortController.create("will abort"), "fake-feishu-card-2")
        @Expect(abortController.abort("cancelled"), true)
        @Expect(abortController.currentPhase(), "aborted")
        @Expect(abortController.patchChunk("ignored after abort"), false)

        let fallbackClient = FeishuFakeApiClient()
        fallbackClient.failNextCardSend("rate_limited", error: "card create failed")
        let fallback = FeishuStreamingCardController(
            fallbackClient,
            accountId: "tenant-a",
            rawPeerId: "oc_stream",
            receiveId: "oc_stream",
            receiveIdType: "chat_id"
        )
        @Expect(fallback.create("fallback text"), "fake-feishu-text-1")
        @Expect(fallback.currentPhase(), "terminated")
        @Expect(fallbackClient.textSendCount(), 1)
    }

    @TestCase
    public func streamingControllerThrottlesDuplicateFlushAndFallsBackOnPatchFailure(): Unit {
        let client = FeishuFakeApiClient()
        let controller = FeishuStreamingCardController(
            client,
            accountId: "tenant-a",
            rawPeerId: "oc_stream",
            receiveId: "oc_stream",
            receiveIdType: "chat_id"
        )
        @Expect(controller.create("first chunk"), "fake-feishu-card-1")
        @Expect(controller.patchChunk("first chunk"), true)
        @Expect(client.cardPatchCount(), 0)

        client.failNextCardPatch("rate_limited", error: "card update rate limited")
        @Expect(controller.patchChunk("second chunk"), true)
        @Expect(controller.currentPhase(), "terminated")
        @Expect(client.cardPatchCount(), 1)
        @Expect(client.textSendCount(), 1)
        @Expect(client.lastTextMessage().contains("second chunk"), true)
    }

    @TestCase
    public func cardFallbackClassificationSeparatesRateTableAndTerminalFailures(): Unit {
        let rate = classifyFeishuCardFallback("rate_limited", error: "card rate limited")
        @Expect(rate.shouldFallback, true)
        @Expect(rate.category, "rate_limit")
        @Expect(rate.status, "rate_limited")

        let table = classifyFeishuCardFallback("table_size_limit", error: "table rows exceeded")
        @Expect(table.shouldFallback, true)
        @Expect(table.category, "table_limit")

        let unavailable = classifyFeishuCardFallback("message_unavailable", error: "message recalled")
        @Expect(unavailable.shouldFallback, true)
        @Expect(unavailable.category, "message_unavailable")

        let invalid = classifyFeishuCardFallback("invalid_payload", error: "bad card json")
        @Expect(invalid.shouldFallback, false)
        @Expect(invalid.category, "unrecoverable")
    }

    @TestCase
    public func streamingControllerRecordsFallbackCategoryForCreateAndPatch(): Unit {
        let createClient = FeishuFakeApiClient()
        createClient.failNextCardSend("too_many_requests", error: "429")
        let createController = FeishuStreamingCardController(
            createClient,
            accountId: "tenant-a",
            rawPeerId: "oc_stream",
            receiveId: "oc_stream",
            receiveIdType: "chat_id"
        )
        @Expect(createController.create("fallback text"), "fake-feishu-text-1")
        @Expect(createController.lastFallbackCategory(), "rate_limit")
        @Expect(createController.lastFallbackStatus(), "too_many_requests")

        let patchClient = FeishuFakeApiClient()
        let patchController = FeishuStreamingCardController(
            patchClient,
            accountId: "tenant-a",
            rawPeerId: "oc_stream",
            receiveId: "oc_stream",
            receiveIdType: "chat_id"
        )
        @Expect(patchController.create("first chunk"), "fake-feishu-card-1")
        patchClient.failNextCardPatch("table_size_limit", error: "table limit exceeded")
        @Expect(patchController.patchChunk("wide table fallback"), true)
        @Expect(patchController.currentPhase(), "terminated")
        @Expect(patchController.lastFallbackCategory(), "table_limit")
        @Expect(patchController.lastFallbackStatus(), "table_size_limit")
        @Expect(patchClient.textSendCount(), 1)
    }

    @TestCase
    public func streamingControllerSupportsFlushThrottleAndMessageIdRecovery(): Unit {
        let client = FeishuFakeApiClient()
        let controller = FeishuStreamingCardController(
            client,
            accountId: "tenant-a",
            rawPeerId: "oc_stream",
            receiveId: "oc_stream",
            receiveIdType: "chat_id"
        )
        @Expect(controller.patchChunkThrottled("before recovery", nowMs: 1000, throttleMs: 500), false)
        @Expect(controller.recoverCardMessageId("om_recovered_card"), true)
        @Expect(controller.currentPhase(), "streaming")
        @Expect(controller.patchChunkThrottled("first visible chunk", nowMs: 1000, throttleMs: 500), true)
        @Expect(client.cardPatchCount(), 1)
        @Expect(controller.patchChunkThrottled("second staged chunk", nowMs: 1100, throttleMs: 500), true)
        @Expect(client.cardPatchCount(), 1)
        @Expect(controller.flushPending(nowMs: 1600), true)
        @Expect(client.cardPatchCount(), 2)
        @Expect(client.patchedCard(1).fallbackText().contains("second staged chunk"), true)
    }

    @TestCase
    public func streamingControllerExposesCardKitFlushFallbackAndUnavailableState(): Unit {
        let client = FeishuFakeApiClient()
        let controller = FeishuStreamingCardController(
            client,
            accountId: "tenant-a",
            rawPeerId: "oc_stream",
            receiveId: "oc_stream",
            receiveIdType: "chat_id",
            replyToMessageId: Some("om_source")
        )

        let idle = controller.observableState()
        @Expect(idle.get("phase").getOrThrow().asString().getValue(), "idle")
        @Expect(idle.get("cardKit").getOrThrow().asObject().get("status").getOrThrow().asString().getValue(), "not_created")
        @Expect(idle.get("unavailable").getOrThrow().asObject().get("terminated").getOrThrow().asBool().getValue(), false)

        @Expect(controller.create("first chunk"), "fake-feishu-card-1")
        @Expect(controller.patchChunkThrottled("second chunk", nowMs: 1000, throttleMs: 500), true)
        @Expect(controller.patchChunkThrottled("third chunk", nowMs: 1100, throttleMs: 500), true)
        let staged = controller.observableState()
        let stagedCardKit = staged.get("cardKit").getOrThrow().asObject()
        let stagedText = staged.get("text").getOrThrow().asObject()
        let stagedFlush = staged.get("flush").getOrThrow().asObject()
        @Expect(staged.get("phase").getOrThrow().asString().getValue(), "streaming")
        @Expect(stagedCardKit.get("cardMessageId").getOrThrow().asString().getValue(), "fake-feishu-card-1")
        @Expect(stagedCardKit.get("sequence").getOrThrow().asInt().getValue(), 2)
        @Expect(stagedText.get("currentText").getOrThrow().asString().getValue(), "third chunk")
        @Expect(stagedFlush.get("pending").getOrThrow().asBool().getValue(), true)
        @Expect(stagedFlush.get("pendingText").getOrThrow().asString().getValue(), "third chunk")
        @Expect(stagedFlush.get("throttleMs").getOrThrow().asInt().getValue(), 500)

        client.failNextCardPatch("message_unavailable", error: "message recalled")
        @Expect(controller.flushPending(nowMs: 1600), true)
        let terminated = controller.observableState()
        let unavailable = terminated.get("unavailable").getOrThrow().asObject()
        let fallback = terminated.get("fallback").getOrThrow().asObject()
        @Expect(terminated.get("phase").getOrThrow().asString().getValue(), "terminated")
        @Expect(unavailable.get("terminated").getOrThrow().asBool().getValue(), true)
        @Expect(unavailable.get("source").getOrThrow().asString().getValue(), "flush")
        @Expect(unavailable.get("status").getOrThrow().asString().getValue(), "message_unavailable")
        @Expect(fallback.get("category").getOrThrow().asString().getValue(), "message_unavailable")
        @Expect(client.textSendCount(), 1)
        @Expect(client.lastTextMessage().contains("third chunk"), true)
    }

    @TestCase
    public func cardImageResolverCachesImageKeysAndNeverFetchesByDefault(): Unit {
        let resolver = FeishuCardImageResolver()
        resolver.registerResolved("https://assets.example.test/diagram.png", "img_uploaded")
        let resolved = resolver.resolveImages(
            "A ![diagram](https://assets.example.test/diagram.png) ![known](img_known) ![local](file:///tmp/private.png) ![pending](https://assets.example.test/pending.png)"
        )
        @Expect(resolved.contains("![diagram](img_uploaded)"), true)
        @Expect(resolved.contains("![known](img_known)"), true)
        @Expect(resolved.contains("assets.example.test"), false)
        @Expect(resolved.contains("file:///tmp/private.png"), false)
        let state = resolver.toJson()
        @Expect(state.get("resolvedCount").getOrThrow().asInt().getValue(), 1)
        @Expect(state.get("pendingCount").getOrThrow().asInt().getValue(), 1)
        @Expect(state.get("skippedCount").getOrThrow().asInt().getValue(), 1)
        @Expect(state.get("networkEnabled").getOrThrow().asBool().getValue(), false)

        let client = FeishuFakeApiClient()
        let controller = FeishuStreamingCardController(
            client,
            accountId: "tenant-a",
            rawPeerId: "oc_stream",
            receiveId: "oc_stream",
            receiveIdType: "chat_id"
        )
        controller.registerResolvedImage("https://assets.example.test/diagram.png", "img_uploaded")
        @Expect(controller.create("final ![diagram](https://assets.example.test/diagram.png) ![pending](https://assets.example.test/pending.png)"), "fake-feishu-card-1")
        @Expect(client.sentCard(0).fallbackText().contains("![diagram](img_uploaded)"), true)
        @Expect(client.sentCard(0).fallbackText().contains("assets.example.test"), false)
        let controllerImages = controller.observableState().get("imageResolver").getOrThrow().asObject()
        @Expect(controllerImages.get("resolvedCount").getOrThrow().asInt().getValue(), 1)
        @Expect(controllerImages.get("pendingCount").getOrThrow().asInt().getValue(), 1)
    }

    @TestCase
    public func streamingControllerPreservesLongTextMarkdownTableImagesAndRateLimitFallback(): Unit {
        let client = FeishuFakeApiClient()
        let controller = FeishuStreamingCardController(
            client,
            accountId: "tenant-a",
            rawPeerId: "oc_stream",
            receiveId: "oc_stream",
            receiveIdType: "chat_id"
        )
        controller.registerResolvedImage("https://assets.example.test/table.png", "img_table")
        let longText = StringBuilder()
        for (i in 0..80) {
            longText.append("line ${i}: Feishu CardKit streaming parity keeps long text observable.\n")
        }

        @Expect(controller.create(longText.toString()), "fake-feishu-card-1")
        @Expect(client.sentCard(0).fallbackText().contains("line 79"), true)

        let markdownTable =
            "| Item | Status |\n" +
            "| --- | --- |\n" +
            "| create | ok |\n" +
            "| patch | rate-limited fallback |\n" +
            "![table](https://assets.example.test/table.png)"
        client.failNextCardPatch("rate_limited", error: "429 too many card updates")
        @Expect(controller.patchChunk(markdownTable), true)
        @Expect(controller.currentPhase(), "terminated")
        @Expect(controller.lastFallbackCategory(), "rate_limit")
        @Expect(client.cardPatchCount(), 1)
        @Expect(client.textSendCount(), 1)
        @Expect(client.lastTextMessage().contains("| patch | rate-limited fallback |"), true)
        @Expect(client.lastTextMessage().contains("![table](img_table)"), true)
        @Expect(client.lastTextMessage().contains("assets.example.test"), false)
    }

    @TestCase
    public func cardLiveSmokeChecklistIsExplicitOptInOnly(): Unit {
        let checklist = FeishuCardLiveSmokeChecklist.toJson()
        @Expect(checklist.get("optInRequired").getOrThrow().asBool().getValue(), true)
        @Expect(checklist.get("defaultNetwork").getOrThrow().asString().getValue(), "disabled")
        let phases = checklist.get("phases").getOrThrow().asArray()
        @Expect(phases.size(), 7)
        @Expect(checklist.toJsonString().contains("create"), true)
        @Expect(checklist.toJsonString().contains("stream_patch"), true)
        @Expect(checklist.toJsonString().contains("final_update"), true)
        @Expect(checklist.toJsonString().contains("message_unavailable"), true)
        @Expect(checklist.toJsonString().contains("image_resolver"), true)
        @Expect(checklist.toJsonString().contains("fallback"), true)
        @Expect(FeishuCardLiveSmokeChecklist.isOptInValueEnabled(""), false)
        @Expect(FeishuCardLiveSmokeChecklist.isOptInValueEnabled("0"), false)
        @Expect(FeishuCardLiveSmokeChecklist.isOptInValueEnabled("true"), true)
        @Expect(FeishuCardLiveSmokeChecklist.isOptInValueEnabled("1"), true)
    }

    @TestCase
    public func cardLiveSmokeMissingExternalResourcesReturnsSkippedDiagnostic(): Unit {
        let report = FeishuCardLiveSmokeChecklist.skippedExternalResourceReport()
        let raw = report.toJsonString()
        @Expect(report.get("status").getOrThrow().asString().getValue(), "skipped")
        @Expect(report.get("reason").getOrThrow().asString().getValue(), "external-resource-required")
        @Expect(report.get("networkAttempted").getOrThrow().asBool().getValue(), false)
        @Expect(report.get("redacted").getOrThrow().asBool().getValue(), true)
        @Expect(raw.contains("test_feishu_group"), true)
        @Expect(raw.contains("card_create_patch_finalize_abort"), true)
        @Expect(raw.contains("appSecret"), false)
        @Expect(raw.contains("Authorization"), false)
    }

    @TestCase
    public func cardKitStreamingPlanDescribesOpenClawLifecycleWithoutNetwork(): Unit {
        let plan = FeishuCardKitStreamingPlan.build(
            accountId: "tenant-a",
            receiveId: "oc_stream",
            receiveIdType: "chat_id",
            card: FeishuInteractiveCard(title: "Metis", text: "initial answer"),
            cardId: "card_live_1",
            messageId: "om_live_1",
            elementId: "metis_stream_body",
            patchContent: "partial answer",
            finalCard: FeishuInteractiveCard(title: "Metis", text: "final answer"),
            abortReason: "operator stopped"
        )
        let root = plan.toJson()
        let raw = root.toJsonString()
        @Expect(root.get("status").getOrThrow().asString().getValue(), "planned")
        @Expect(root.get("networkAttempted").getOrThrow().asBool().getValue(), false)
        @Expect(root.get("accountId").getOrThrow().asString().getValue(), "tenant-a")
        let requests = root.get("requests").getOrThrow().asArray()
        @Expect(requests.size(), 7)
        let createReq = requests[0].asObject()
        let createBody = this.jsonObjectField(createReq, "body")
        @Expect(this.jsonStringField(createBody, "type"), "card_json")
        @Expect(this.jsonStringField(createBody, "data").contains("\"initial answer\""), true)
        let sendReq = requests[1].asObject()
        let sendBody = this.jsonObjectField(sendReq, "body")
        let sendParams = this.jsonObjectField(sendReq, "params")
        let sendContent = this.jsonStringField(sendBody, "content")
        @Expect(this.jsonStringField(sendParams, "receive_id_type"), "chat_id")
        @Expect(sendContent.contains("\"type\":\"card\""), true)
        @Expect(sendContent.contains("\"card_id\":\"card_live_1\""), true)
        let patchReq = requests[2].asObject()
        let patchBody = this.jsonObjectField(patchReq, "body")
        @Expect(this.jsonStringField(patchReq, "stage"), "stream_patch")
        @Expect(patchBody.get("sequence").getOrThrow().asInt().getValue(), 2)
        let settingsReq = requests[3].asObject()
        let settingsBody = this.jsonObjectField(settingsReq, "body")
        @Expect(this.jsonStringField(settingsReq, "stage"), "settings_close")
        @Expect(this.jsonStringField(settingsReq, "api"), "cardkit.v1.card.settings")
        @Expect(this.jsonStringField(settingsBody, "settings"), "{\"streaming_mode\":false}")
        @Expect(settingsBody.get("sequence").getOrThrow().asInt().getValue(), 3)
        let finalReq = requests[4].asObject()
        let finalBody = this.jsonObjectField(finalReq, "body")
        let finalCard = this.jsonObjectField(finalBody, "card")
        @Expect(this.jsonStringField(finalReq, "stage"), "final_update")
        @Expect(this.jsonStringField(finalCard, "type"), "card_json")
        @Expect(this.jsonStringField(finalCard, "data").contains("\"final answer\""), true)
        @Expect(finalBody.get("sequence").getOrThrow().asInt().getValue(), 4)
        let abortReq = requests[5].asObject()
        let abortBody = this.jsonObjectField(abortReq, "body")
        let abortCard = this.jsonObjectField(abortBody, "card")
        @Expect(this.jsonStringField(abortReq, "stage"), "abort_update")
        @Expect(this.jsonStringField(abortCard, "type"), "card_json")
        @Expect(this.jsonStringField(abortCard, "data").contains("operator stopped"), true)
        @Expect(raw.contains("cardkit.v1.card.create"), true)
        @Expect(raw.contains("im.message.create(interactive.cardkit)"), true)
        @Expect(raw.contains("cardkit.v1.cardElement.content"), true)
        @Expect(raw.contains("cardkit.v1.card.update"), true)
        @Expect(raw.contains("cardkit.v1.card.settings"), true)
        @Expect(raw.contains("abort_update"), true)
        @Expect(raw.contains("fallback_text"), true)
        @Expect(raw.contains("metis_stream_body"), true)
        @Expect(raw.contains("Authorization"), false)
        @Expect(raw.contains("tenant-secret"), false)
    }

    @TestCase
    public func cardFallbackClassificationRedactsSensitiveDetails(): Unit {
        let decision = classifyFeishuCardFallback(
            "rate_limited",
            error: "Authorization: Bearer live-token tenant_secret=abc appSecret=def"
        )
        @Expect(decision.shouldFallback, true)
        @Expect(decision.category, "rate_limit")
        @Expect(decision.detail, "[redacted]")
        @Expect(decision.detail.contains("live-token"), false)
        @Expect(decision.detail.contains("tenant_secret"), false)
        @Expect(decision.detail.contains("appSecret"), false)
    }

    @TestCase
    public func eventReplayLiveSmokeChecklistIsExplicitOptInOnly(): Unit {
        let checklist = FeishuEventReplayLiveSmokeChecklist.toJson()
        @Expect(checklist.get("optInRequired").getOrThrow().asBool().getValue(), true)
        @Expect(checklist.get("optInEnv").getOrThrow().asString().getValue(), "METIS_FEISHU_LIVE_EVENT_REPLAY_SMOKE")
        @Expect(checklist.get("defaultNetwork").getOrThrow().asString().getValue(), "disabled")
        @Expect(checklist.toJsonString().contains("redacted"), true)
        let matrix = checklist.get("matrix").getOrThrow().asArray()
        @Expect(matrix.size(), 12)
        @Expect(checklist.toJsonString().contains("post"), true)
        @Expect(checklist.toJsonString().contains("interactive"), true)
        @Expect(checklist.toJsonString().contains("file"), true)
        @Expect(checklist.toJsonString().contains("audio"), true)
        @Expect(checklist.toJsonString().contains("video"), true)
        @Expect(FeishuEventReplayLiveSmokeChecklist.isOptInValueEnabled(""), false)
        @Expect(FeishuEventReplayLiveSmokeChecklist.isOptInValueEnabled("yes"), true)
    }

    @TestCase
    public func eventReplayLiveSmokeMissingExternalResourcesReturnsSkippedDiagnostic(): Unit {
        let report = FeishuEventReplayLiveSmokeChecklist.skippedExternalResourceReport()
        let raw = report.toJsonString()
        @Expect(report.get("status").getOrThrow().asString().getValue(), "skipped")
        @Expect(report.get("reason").getOrThrow().asString().getValue(), "external-resource-required")
        @Expect(report.get("networkAttempted").getOrThrow().asBool().getValue(), false)
        @Expect(report.get("redacted").getOrThrow().asBool().getValue(), true)
        @Expect(raw.contains("test_event_subscription"), true)
        @Expect(raw.contains("message/post/image/file/audio/video/card/reaction/drive/membership/vc/bitable"), true)
        @Expect(raw.contains("quote"), true)
        @Expect(raw.contains("merged_forward"), true)
        @Expect(raw.contains("resource_fetch_diagnostics"), true)
        @Expect(raw.contains("tenant_access_token"), false)
        @Expect(raw.contains("Authorization"), false)
    }

    @TestCase
    public func streamingControllerUnavailableMessageGuardTerminatesWithoutLosingFinalAnswer(): Unit {
        let client = FeishuFakeApiClient()
        let controller = FeishuStreamingCardController(
            client,
            accountId: "tenant-a",
            rawPeerId: "oc_stream",
            receiveId: "oc_stream",
            receiveIdType: "chat_id"
        )
        @Expect(controller.create("first chunk"), "fake-feishu-card-1")
        client.failNextCardPatch("message_unavailable", error: "message recalled")
        @Expect(controller.finalize("final answer"), true)
        @Expect(controller.currentPhase(), "terminated")
        @Expect(client.textSendCount(), 1)
        @Expect(client.lastTextMessage().contains("final answer"), true)
    }

    @TestCase
    public func footerMetricsRespectConfiguredFieldsAndPresentData(): Unit {
        let metrics = FeishuReplyFooterMetrics(
            status: "completed",
            elapsedMs: 1500,
            inputTokens: 10,
            outputTokens: 20,
            cacheRead: 5,
            cacheWrite: 6,
            contextTokens: 100,
            model: "metis-test"
        )
        let onlyStatusAndModel = metrics.toFooterText(config: FeishuReplyFooterConfig(status: true, elapsed: false, tokens: false, cache: false, context: false, model: true))
        @Expect(onlyStatusAndModel.contains("Status: completed"), true)
        @Expect(onlyStatusAndModel.contains("Model: metis-test"), true)
        @Expect(onlyStatusAndModel.contains("Tokens in"), false)
        @Expect(onlyStatusAndModel.contains("Elapsed"), false)

        let noData = FeishuReplyFooterMetrics().toFooterText(config: FeishuReplyFooterConfig(status: true, elapsed: true, tokens: true, cache: true, context: true, model: true))
        @Expect(noData, "")
    }

    @TestCase
    public func streamingControllerObservableStateIncludesFooterMetricsSnapshot(): Unit {
        let client = FeishuFakeApiClient()
        let controller = FeishuStreamingCardController(
            client,
            accountId: "tenant-a",
            rawPeerId: "oc_stream",
            receiveId: "oc_stream",
            receiveIdType: "chat_id"
        )
        @Expect(controller.create("first"), "fake-feishu-card-1")
        @Expect(controller.finalize("final", footerMetrics: Some(FeishuReplyFooterMetrics(
            status: "completed",
            elapsedMs: 2000,
            inputTokens: 11,
            outputTokens: 22,
            cacheRead: 3,
            cacheWrite: 4,
            contextTokens: 8192,
            model: "metis-observable"
        ))), true)
        let metrics = controller.observableState().get("footerMetrics").getOrThrow().asObject()
        @Expect(metrics.get("status").getOrThrow().asString().getValue(), "completed")
        @Expect(metrics.get("inputTokens").getOrThrow().asInt().getValue(), 11)
        @Expect(metrics.get("outputTokens").getOrThrow().asInt().getValue(), 22)
        @Expect(metrics.get("cacheRead").getOrThrow().asInt().getValue(), 3)
        @Expect(metrics.get("cacheWrite").getOrThrow().asInt().getValue(), 4)
        @Expect(metrics.get("contextTokens").getOrThrow().asInt().getValue(), 8192)
        @Expect(metrics.get("model").getOrThrow().asString().getValue(), "metis-observable")
    }

    @TestCase
    public func toolUseDisplayIsIncludedOnlyWhenEnabled(): Unit {
        let hidden = FeishuReplyCardDraft(title: "Metis", showToolUse: false)
        hidden.appendText("answer")
        hidden.appendToolUse("feishu_im_user_fetch_resource", "{\"message_id\":\"om_1\"}")
        @Expect(hidden.toCard().fallbackText().contains("feishu_im_user_fetch_resource"), false)

        let visible = FeishuReplyCardDraft(title: "Metis", showToolUse: true)
        visible.appendText("answer")
        visible.appendToolUse("feishu_im_user_fetch_resource", "{\"message_id\":\"om_1\"}")
        let card = visible.toCard()
        @Expect(card.fallbackText().contains("answer"), true)
        @Expect(card.fallbackText().contains("Tool use"), true)
        @Expect(card.fallbackText().contains("feishu_im_user_fetch_resource"), true)
    }

    @TestCase
    public func cardActionTriggerBecomesSafeSystemEvent(): Unit {
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true), accountId: "tenant-a")
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(this.cardActionPayload("feishu.auth.confirm")).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].systemEvent, true)
        @Expect(inbound[0].systemEventKind, "feishu.card_action")
        @Expect(inbound[0].accountId, "tenant-a")
        @Expect(inbound[0].peerId, "oc_card")
        @Expect(inbound[0].text.contains("[feishu-card-action]"), true)
        let action = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuCardAction").getOrThrow().asObject()
        @Expect(action.get("action").getOrThrow().asString().getValue(), "feishu.auth.confirm")
        @Expect(action.get("operatorId").getOrThrow().asString().getValue(), "ou_operator")
    }

    @TestCase
    public func reactionAndDriveCommentEventsBecomeSafeSystemEvents(): Unit {
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true), accountId: "tenant-a")
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(this.reactionPayload()).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(this.driveCommentPayload()).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 2)
        @Expect(inbound[0].systemEvent, true)
        @Expect(inbound[0].systemEventKind, "feishu.reaction")
        @Expect(inbound[0].peerId, "oc_react")
        @Expect(inbound[0].threadId.getOrThrow(), "omt_react")
        @Expect(inbound[0].text.contains("THUMBSUP"), true)
        let reaction = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuReaction").getOrThrow().asObject()
        @Expect(reaction.get("messageId").getOrThrow().asString().getValue(), "om_reacted")
        @Expect(reaction.get("operatorId").getOrThrow().asString().getValue(), "ou_reactor")

        @Expect(inbound[1].systemEvent, true)
        @Expect(inbound[1].systemEventKind, "feishu.drive_comment")
        @Expect(inbound[1].mentioned, true)
        @Expect(inbound[1].text.contains("comment_1"), true)
        let comment = inbound[1].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuDriveComment").getOrThrow().asObject()
        @Expect(comment.get("fileToken").getOrThrow().asString().getValue(), "doccn_1")
        @Expect(comment.get("replyId").getOrThrow().asString().getValue(), "reply_1")
    }

    @TestCase
    public func inboundEnvelopeRejectsWrongAppForMultiAccountFakeEvents(): Unit {
        let tenantA = JsonObject()
        tenantA.put("appId", JsonString("cli_app_a"))
        let tenantB = JsonObject()
        tenantB.put("appId", JsonString("cli_app_b"))
        let accounts = JsonObject()
        accounts.put("tenant-a", tenantA)
        accounts.put("tenant-b", tenantB)
        let adapter = FeishuAdapter(
            config: FeishuConfig(enabled: true, accounts: Some(accounts)),
            accountId: "tenant-a"
        )
        adapter.start()

        let wrong = adapter.ingestWebhookPayload(this.webhookPayload(
            "om_wrong_app",
            "oc_group",
            "ou_1",
            "{\\\"text\\\":\\\"wrong app\\\"}",
            headerAccountId: "tenant-a",
            appId: "cli_app_b"
        ))
        let wrongJson = JsonValue.fromStr(wrong).asObject()
        @Expect(wrongJson.get("ignored").getOrThrow().asBool().getValue(), true)
        @Expect(wrongJson.get("reason").getOrThrow().asString().getValue(), "wrong_app")
        @Expect(adapter.pullInbound().size, 0)

        @Expect(adapter.ingestWebhookPayload(this.webhookPayload(
            "om_right_app",
            "oc_group",
            "ou_1",
            "{\\\"text\\\":\\\"right app\\\"}",
            headerAccountId: "tenant-a",
            appId: "cli_app_a"
        )).contains("\"ok\":true"), true)
        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].messageId, "om_right_app")
        @Expect(inbound[0].accountId, "tenant-a")
    }

    @TestCase
    public func accountResolverMarksExplicitEmptyGroupAllowFromAndGroupsAsLocalSecurity(): Unit {
        let topGroups = JsonObject()
        let oldGroup = JsonObject()
        oldGroup.put("enabled", JsonBool(true))
        topGroups.put("oc_old", oldGroup)
        let writer = JsonObject()
        writer.put("groupAllowFrom", JsonArray([]))
        writer.put("groups", JsonObject())
        let accounts = JsonObject()
        accounts.put("feishuWriter", writer)

        let resolved = gatewayFeishuResolveAccount(
            FeishuConfig(
                enabled: true,
                groupPolicy: "allowlist",
                groupAllowFrom: ["oc_old"],
                groups: Some(topGroups),
                accounts: Some(accounts)
            ),
            "feishuWriter"
        )

        @Expect(resolved.config.groupAllowFrom.size, 0)
        @Expect(resolved.config.groups.getOrThrow().size(), 0)
        @Expect(resolved.securitySources.get("groupAllowFrom").getOrThrow().asString().getValue(), "explicit-empty")
        @Expect(resolved.securitySources.get("groups").getOrThrow().asString().getValue(), "explicit-empty")
        @Expect(resolved.securityEffective.get("groupAllowFrom").getOrThrow().asArray().size(), 0)
        @Expect(resolved.securityEffective.get("groups").getOrThrow().asObject().size(), 0)
    }

    @TestCase
    public func dmGateUsesAccountLocalExplicitEmptyAllowFromInsteadOfTopLevel(): Unit {
        let writer = JsonObject()
        writer.put("allowFrom", JsonArray([]))
        let accounts = JsonObject()
        accounts.put("feishuWriter", writer)
        let adapter = FeishuAdapter(
            config: FeishuConfig(enabled: true, dmPolicy: "pairing", allowFrom: ["ou_old"], accounts: Some(accounts)),
            accountId: "feishuWriter"
        )
        adapter.start()

        @Expect(adapter.ingestWebhookPayload(this.webhookPayload(
            "om_dm_block",
            "ou_old",
            "ou_old",
            "{\\\"text\\\":\\\"hello\\\"}",
            chatType: "p2p",
            headerAccountId: "feishuWriter"
        )).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        let gate = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuGate").getOrThrow().asObject()
        @Expect(gate.get("triggerAgent").getOrThrow().asBool().getValue(), false)
        @Expect(gate.get("reason").getOrThrow().asString().getValue(), "dm_pairing_required")
        @Expect(gate.get("allowFrom").getOrThrow().asArray().size(), 0)
    }

    @TestCase
    public func groupGateUsesAccountLocalAllowlistInsteadOfTopLevel(): Unit {
        let writer = JsonObject()
        writer.put("groupPolicy", JsonString("allowlist"))
        writer.put("groupAllowFrom", JsonArray([]))
        writer.put("requireMention", JsonBool(false))
        let accounts = JsonObject()
        accounts.put("feishuWriter", writer)
        let adapter = FeishuAdapter(
            config: FeishuConfig(enabled: true, groupPolicy: "allowlist", groupAllowFrom: ["oc_old"], accounts: Some(accounts)),
            accountId: "feishuWriter"
        )
        adapter.start()

        @Expect(adapter.ingestWebhookPayload(this.webhookPayload(
            "om_group_block",
            "oc_old",
            "ou_1",
            "{\\\"text\\\":\\\"hello\\\"}",
            headerAccountId: "feishuWriter"
        )).contains("\"ok\":true"), true)
        let blocked = adapter.pullInbound()
        @Expect(blocked.size, 1)
        let blockedGate = blocked[0].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuGate").getOrThrow().asObject()
        @Expect(blockedGate.get("triggerAgent").getOrThrow().asBool().getValue(), false)
        @Expect(blockedGate.get("reason").getOrThrow().asString().getValue(), "group_not_allowed")

        let allowed = JsonArray([])
        allowed.add(JsonString("oc_writer"))
        writer.put("groupAllowFrom", allowed)
        let allowedAdapter = FeishuAdapter(
            config: FeishuConfig(enabled: true, groupPolicy: "allowlist", groupAllowFrom: ["oc_old"], accounts: Some(accounts)),
            accountId: "feishuWriter"
        )
        allowedAdapter.start()
        @Expect(allowedAdapter.ingestWebhookPayload(this.webhookPayload(
            "om_group_allow",
            "oc_writer",
            "ou_1",
            "{\\\"text\\\":\\\"hello\\\"}",
            headerAccountId: "feishuWriter"
        )).contains("\"ok\":true"), true)
        let passed = allowedAdapter.pullInbound()
        @Expect(passed.size, 1)
        let passedGate = passed[0].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuGate").getOrThrow().asObject()
        @Expect(passedGate.get("triggerAgent").getOrThrow().asBool().getValue(), true)
        @Expect(passedGate.get("reason").getOrThrow().asString().getValue(), "accepted")
    }

    @TestCase
    public func messageAndReactionDedupDropReconnectReplayDeterministically(): Unit {
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true), accountId: "tenant-a")
        adapter.start()
        let messagePayload = this.webhookPayload("om_dup", "oc_group", "ou_1", "{\\\"text\\\":\\\"hello\\\"}")
        @Expect(adapter.ingestWebhookPayload(messagePayload).contains("\"ok\":true"), true)
        let messageDup = JsonValue.fromStr(adapter.ingestWebhookPayload(messagePayload)).asObject()
        @Expect(messageDup.get("ignored").getOrThrow().asBool().getValue(), true)
        @Expect(messageDup.get("reason").getOrThrow().asString().getValue(), "duplicate_event")

        let reactionPayload = this.reactionPayload()
        @Expect(adapter.ingestWebhookPayload(reactionPayload).contains("\"ok\":true"), true)
        let reactionDup = JsonValue.fromStr(adapter.ingestWebhookPayload(reactionPayload)).asObject()
        @Expect(reactionDup.get("ignored").getOrThrow().asBool().getValue(), true)
        @Expect(reactionDup.get("reason").getOrThrow().asString().getValue(), "duplicate_event")

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 2)
    }

    @TestCase
    public func staleMessageAndReactionReplayAreIgnoredWithDiagnostics(): Unit {
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true), accountId: "tenant-a")
        adapter.start()
        let staleMessage = JsonValue.fromStr(adapter.ingestWebhookPayload(this.webhookPayload(
            "om_stale",
            "oc_group",
            "ou_1",
            "{\\\"text\\\":\\\"old\\\"}",
            createTime: "1"
        ))).asObject()
        @Expect(staleMessage.get("ignored").getOrThrow().asBool().getValue(), true)
        @Expect(staleMessage.get("reason").getOrThrow().asString().getValue(), "stale_event")

        let staleReaction = JsonValue.fromStr(adapter.ingestWebhookPayload(this.reactionPayload(actionTime: "1"))).asObject()
        @Expect(staleReaction.get("ignored").getOrThrow().asBool().getValue(), true)
        @Expect(staleReaction.get("reason").getOrThrow().asString().getValue(), "stale_event")
        @Expect(adapter.pullInbound().size, 0)
    }

    @TestCase
    public func botVcAndBitableEventsBecomeStructuredSystemEvents(): Unit {
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true), accountId: "tenant-a")
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(this.botMembershipPayload("im.chat.member.bot.added_v1")).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(this.botMembershipPayload("im.chat.member.bot.deleted_v1")).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(this.vcInvitedPayload()).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(this.bitableFieldChangedPayload()).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 4)
        @Expect(inbound[0].systemEventKind, "feishu.bot_membership")
        @Expect(inbound[0].text.contains("added"), true)
        @Expect(inbound[1].systemEventKind, "feishu.bot_membership")
        @Expect(inbound[1].text.contains("deleted"), true)
        @Expect(inbound[2].systemEventKind, "feishu.vc_invited")
        @Expect(inbound[2].text.contains("123456"), true)
        @Expect(inbound[3].systemEventKind, "feishu.bitable_field_changed")
        @Expect(inbound[3].text.contains("fld_1"), true)
    }

    @TestCase
    public func unsupportedAndMalformedEventsReturnExplicitIgnoredDiagnostics(): Unit {
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true))
        adapter.start()

        let unsupportedEvent =
            "{" +
            "\"header\":{\"event_type\":\"im.message.deleted_v1\"}," +
            "\"event\":{\"message_id\":\"om_deleted\"}" +
            "}"
        let unsupported = adapter.ingestWebhookPayload(unsupportedEvent)
        let unsupportedJson = JsonValue.fromStr(unsupported).asObject()
        @Expect(unsupportedJson.get("ignored").getOrThrow().asBool().getValue(), true)
        @Expect(unsupportedJson.get("reason").getOrThrow().asString().getValue(), "unsupported_event")
        @Expect(unsupportedJson.get("eventType").getOrThrow().asString().getValue(), "im.message.deleted_v1")

        let unsupportedMessage = adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_location",
                "oc_group",
                "ou_1",
                "{\\\"name\\\":\\\"office\\\"}",
                messageType: "location"
            )
        )
        let unsupportedMessageJson = JsonValue.fromStr(unsupportedMessage).asObject()
        @Expect(unsupportedMessageJson.get("ignored").getOrThrow().asBool().getValue(), true)
        @Expect(unsupportedMessageJson.get("reason").getOrThrow().asString().getValue(), "unsupported_message_type")
        @Expect(unsupportedMessageJson.get("messageType").getOrThrow().asString().getValue(), "location")

        let malformedMessage =
            "{" +
            "\"header\":{\"event_type\":\"im.message.receive_v1\"}," +
            "\"event\":{\"message\":{\"message_type\":\"text\",\"content\":\"{\\\"text\\\":\\\"missing sender\\\"}\"}}" +
            "}"
        let malformed = adapter.ingestWebhookPayload(malformedMessage)
        let malformedJson = JsonValue.fromStr(malformed).asObject()
        @Expect(malformedJson.get("ignored").getOrThrow().asBool().getValue(), true)
        @Expect(malformedJson.get("reason").getOrThrow().asString().getValue(), "malformed_event")
    }

    @TestCase
    public func sanitizedFeishuEventReplayFixtureCoversSupportedAndIgnoredShapes(): Unit {
        let raw = String.fromUtf8(File.readFrom(Path("src/gateway/channels/feishu/feishu_event_replay_samples.json")))
        @Expect(raw.contains("Bearer "), false)
        @Expect(raw.contains("tenant_access_token"), false)
        @Expect(raw.contains("app_secret"), false)
        @Expect(raw.contains("Authorization"), false)

        let samples = JsonValue.fromStr(raw).asArray()
        let tenant = JsonObject()
        tenant.put("appId", JsonString("cli_app_a"))
        let accounts = JsonObject()
        accounts.put("tenant-a", tenant)
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true, accounts: Some(accounts)), accountId: "tenant-a")
        adapter.start()
        let expectedInbound = ArrayList<JsonObject>()
        var ignoredCount = 0
        for (item in samples.getItems()) {
            let sample = item.asObject()
            let payload = sample.get("payload").getOrThrow().asObject().toJsonString()
            let expected = sample.get("expected").getOrThrow().asObject()
            let response = JsonValue.fromStr(adapter.ingestWebhookPayload(payload)).asObject()
            if (expected.get("ignored").getOrThrow().asBool().getValue()) {
                ignoredCount += 1
                @Expect(response.get("ignored").getOrThrow().asBool().getValue(), true)
                @Expect(response.get("reason").getOrThrow().asString().getValue(), expected.get("reason").getOrThrow().asString().getValue())
            } else {
                @Expect(response.get("ok").getOrThrow().asBool().getValue(), true)
                expectedInbound.add(expected)
                if (this.fixtureBool(expected, "dedup", false)) {
                    let duplicate = JsonValue.fromStr(adapter.ingestWebhookPayload(payload)).asObject()
                    @Expect(duplicate.get("ignored").getOrThrow().asBool().getValue(), true)
                    @Expect(duplicate.get("reason").getOrThrow().asString().getValue(), "duplicate_event")
                }
            }
        }

        let inbound = adapter.pullInbound()
        @Expect(samples.size(), 16)
        @Expect(ignoredCount, 3)
        @Expect(inbound.size, expectedInbound.size)
        @Expect(inbound.size, 13)
        for (i in 0..inbound.size) {
            this.expectFixtureInbound(inbound[i], expectedInbound[i])
        }
        @Expect(inbound[0].text.contains("fixture hello"), true)
        @Expect(inbound[1].text.contains("fixture post"), true)
        @Expect(inbound[5].text.contains("fixture card text"), true)
        @Expect(inbound[12].mediaContext.get("records").getOrThrow().asArray()[0].asObject()
            .get("skippedReason").getOrThrow().asString().getValue(), "metadata_only")
    }

    @TestCase
    public func webhookThreadPayloadProjectsUnifiedImRouteContext(): Unit {
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true))
        adapter.start()
        let payload =
            "{" +
            "\"header\":{\"event_type\":\"im.message.receive_v1\"}," +
            "\"event\":{" +
            "\"sender\":{\"sender_id\":{\"open_id\":\"ou_123\"}}," +
            "\"message\":{" +
            "\"message_id\":\"om_1\"," +
            "\"chat_id\":\"oc_a\"," +
            "\"chat_type\":\"group\"," +
            "\"message_type\":\"text\"," +
            "\"content\":\"{\\\"text\\\":\\\"hello\\\"}\"," +
            "\"root_id\":\"\"," +
            "\"thread_id\":\"thread_x\"" +
            "}" +
            "}" +
            "}"

        @Expect(adapter.ingestWebhookPayload(payload).contains("\"ok\":true"), true)
        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].peerId, "oc_a")
        @Expect(inbound[0].threadId.getOrThrow(), "thread_x")
        let imRoute = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("imRoute").getOrThrow().asObject()
        @Expect(imRoute.get("channel").getOrThrow().asString().getValue(), "feishu")
        @Expect(imRoute.get("accountId").getOrThrow().asString().getValue(), "default")
        @Expect(imRoute.get("peerKind").getOrThrow().asString().getValue(), "thread")
        @Expect(imRoute.get("peerId").getOrThrow().asString().getValue(), "thread_x")
        @Expect(imRoute.get("parentPeerKind").getOrThrow().asString().getValue(), "group")
        @Expect(imRoute.get("parentPeerId").getOrThrow().asString().getValue(), "oc_a")
        @Expect(imRoute.get("senderId").getOrThrow().asString().getValue(), "ou_123")
        @Expect(imRoute.get("messageId").getOrThrow().asString().getValue(), "om_1")
    }

    @TestCase
    public func webhookRouteContextUsesConfiguredAndInboundAccountIds(): Unit {
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true), accountId: "work")
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload("om_work", "oc_a", "ou_1", "{\\\"text\\\":\\\"hello\\\"}")
        ).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_inbound",
                "oc_a",
                "ou_2",
                "{\\\"text\\\":\\\"hello\\\"}",
                headerAccountId: "tenant-b"
            )
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 2)
        @Expect(inbound[0].accountId, "work")
        @Expect(inbound[1].accountId, "tenant-b")
        let workRoute = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("imRoute").getOrThrow().asObject()
        let tenantRoute = inbound[1].mediaContext.get("context").getOrThrow().asObject()
            .get("imRoute").getOrThrow().asObject()
        @Expect(workRoute.get("accountId").getOrThrow().asString().getValue(), "work")
        @Expect(workRoute.get("defaultAccountId").getOrThrow().asString().getValue(), "work")
        @Expect(tenantRoute.get("accountId").getOrThrow().asString().getValue(), "tenant-b")
        @Expect(inbound[0].mediaContext.get("accountId").getOrThrow().asString().getValue(), "work")
    }

    @TestCase
    public func groupThreadKeepsThreadPeerAndReplyInThread(): Unit {
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true))
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload("om_thread", "oc_group", "ou_1", "{\\\"text\\\":\\\"hello\\\"}", threadId: "omt_topic")
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].threadId.getOrThrow(), "omt_topic")
        @Expect(inbound[0].replyInThread, true)
        let imRoute = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("imRoute").getOrThrow().asObject()
        @Expect(imRoute.get("peerKind").getOrThrow().asString().getValue(), "thread")
        @Expect(imRoute.get("parentPeerKind").getOrThrow().asString().getValue(), "group")
        @Expect(imRoute.get("parentPeerId").getOrThrow().asString().getValue(), "oc_group")
    }

    @TestCase
    public func accountChatThreadQueueSerializesOnlySameThread(): Unit {
        let queue = FeishuChatQueue()
        let probe = FeishuQueueProbe()

        let first = spawn {
            queue.runExclusive("work", "oc_group", "omt_1", { =>
                probe.runSameThreadTask(80)
            })
        }
        sleep(Duration.millisecond * 10)
        let second = spawn {
            queue.runExclusive("work", "oc_group", "omt_1", { =>
                probe.runSameThreadTask(20)
            })
        }
        let third = spawn {
            queue.runExclusive("work", "oc_group", "omt_2", { =>
                probe.runOtherThreadTask()
            })
        }
        first.get()
        second.get()
        third.get()

        @Expect(probe.sameOverlap(), false)
        @Expect(probe.otherObservedParallel(), true)
        @Expect(buildFeishuQueueKey("work", "oc_group", "omt_1"), "work:oc_group:thread:omt_1")
    }

    @TestCase
    public func groupRequireMentionGateKeepsDiagnosticWithoutTrigger(): Unit {
        let adapter = FeishuAdapter(
            config: FeishuConfig(
                enabled: true,
                botOpenId: "bot-open",
                groupPolicy: "open",
                policy: ChannelPolicyConfig(requireMentionInGroup: true)
            )
        )
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload("om_gate", "oc_group", "ou_1", "{\\\"text\\\":\\\"plain group message\\\"}")
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].mentioned, false)
        let gate = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuGate").getOrThrow().asObject()
        @Expect(gate.get("triggerAgent").getOrThrow().asBool().getValue(), false)
        @Expect(gate.get("reason").getOrThrow().asString().getValue(), "group_mention_required")
    }

    @TestCase
    public func imageFileMediaAndAudioCreateAttachmentContextWithoutDownload(): Unit {
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true), accountId: "work")
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_image",
                "oc_group",
                "ou_1",
                "{\\\"image_key\\\":\\\"img_v2_1\\\",\\\"file_name\\\":\\\"diagram.png\\\",\\\"mime_type\\\":\\\"image/png\\\"}",
                messageType: "image"
            )
        ).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_file",
                "oc_group",
                "ou_1",
                "{\\\"file_key\\\":\\\"file_v2_1\\\",\\\"file_name\\\":\\\"report.pdf\\\",\\\"mime_type\\\":\\\"application/pdf\\\",\\\"size\\\":64}",
                messageType: "file"
            )
        ).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_media",
                "oc_group",
                "ou_1",
                "{\\\"file_key\\\":\\\"media_v2_1\\\",\\\"file_name\\\":\\\"clip.mp4\\\",\\\"mime_type\\\":\\\"video/mp4\\\"}",
                messageType: "media"
            )
        ).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_audio",
                "oc_group",
                "ou_1",
                "{\\\"file_key\\\":\\\"audio_v2_1\\\",\\\"file_name\\\":\\\"voice.ogg\\\",\\\"mime_type\\\":\\\"audio/ogg\\\"}",
                messageType: "audio"
            )
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 4)
        let imageRecords = inbound[0].mediaContext.get("records").getOrThrow().asArray()
        let image = imageRecords[0].asObject()
        @Expect(image.get("channel").getOrThrow().asString().getValue(), "feishu")
        @Expect(image.get("accountId").getOrThrow().asString().getValue(), "work")
        @Expect(image.get("mediaKind").getOrThrow().asString().getValue(), "image")
        @Expect(image.get("fileId").getOrThrow().asString().getValue(), "img_v2_1")
        @Expect(image.get("originalFileName").getOrThrow().asString().getValue(), "diagram.png")
        @Expect(image.get("mimeType").getOrThrow().asString().getValue(), "image/png")
        @Expect(image.get("downloaded").getOrThrow().asBool().getValue(), false)
        @Expect(image.get("skippedReason").getOrThrow().asString().getValue(), "metadata_only")
        let imageFetch = image.get("resourceFetch").getOrThrow().asObject()
        @Expect(imageFetch.get("status").getOrThrow().asString().getValue(), "metadata_only")
        @Expect(imageFetch.get("networkAttempted").getOrThrow().asBool().getValue(), false)
        @Expect(imageFetch.get("tool").getOrThrow().asString().getValue(), "feishu_im_user_fetch_resource")
        @Expect(imageFetch.get("requiredScopes").getOrThrow().asArray()[0].asString().getValue(), "im:message.resource:read")

        let file = inbound[1].mediaContext.get("records").getOrThrow().asArray()[0].asObject()
        let media = inbound[2].mediaContext.get("records").getOrThrow().asArray()[0].asObject()
        let audio = inbound[3].mediaContext.get("records").getOrThrow().asArray()[0].asObject()
        @Expect(file.get("mediaKind").getOrThrow().asString().getValue(), "file")
        @Expect(file.get("fileSize").getOrThrow().asInt().getValue(), 64)
        @Expect(file.get("resourceFetch").getOrThrow().asObject().get("resourceType").getOrThrow().asString().getValue(), "file")
        @Expect(media.get("mediaKind").getOrThrow().asString().getValue(), "media")
        @Expect(media.get("resourceFetch").getOrThrow().asObject().get("eligibleFor").getOrThrow().asString().getValue(), "video")
        @Expect(audio.get("mediaKind").getOrThrow().asString().getValue(), "audio")
        @Expect(audio.get("resourceFetch").getOrThrow().asObject().get("eligibleFor").getOrThrow().asString().getValue(), "audio")
    }

    @TestCase
    public func supportedMessageTypesProjectRouteSessionAndMediaContext(): Unit {
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true), accountId: "work")
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(this.webhookPayload("om_text_all", "oc_group", "ou_1", "{\\\"text\\\":\\\"plain text\\\"}", messageType: "text")).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(this.webhookPayload("om_post_all", "oc_group", "ou_1", "{\\\"zh_cn\\\":{\\\"content\\\":[[{\\\"tag\\\":\\\"text\\\",\\\"text\\\":\\\"post text\\\"}]]}}", messageType: "post")).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(this.webhookPayload("om_image_all", "oc_group", "ou_1", "{\\\"image_key\\\":\\\"img_all\\\",\\\"file_name\\\":\\\"diagram.png\\\",\\\"mime_type\\\":\\\"image/png\\\"}", messageType: "image")).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(this.webhookPayload("om_file_all", "oc_group", "ou_1", "{\\\"file_key\\\":\\\"file_all\\\",\\\"file_name\\\":\\\"report.pdf\\\",\\\"mime_type\\\":\\\"application/pdf\\\"}", messageType: "file")).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(this.webhookPayload("om_audio_all", "oc_group", "ou_1", "{\\\"file_key\\\":\\\"audio_all\\\",\\\"file_name\\\":\\\"voice.ogg\\\",\\\"mime_type\\\":\\\"audio/ogg\\\"}", messageType: "audio")).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(this.webhookPayload("om_video_all", "oc_group", "ou_1", "{\\\"file_key\\\":\\\"video_all\\\",\\\"file_name\\\":\\\"demo.mp4\\\",\\\"mime_type\\\":\\\"video/mp4\\\"}", messageType: "video")).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(this.webhookPayload("om_media_all", "oc_group", "ou_1", "{\\\"file_key\\\":\\\"media_all\\\",\\\"file_name\\\":\\\"clip.mp4\\\",\\\"mime_type\\\":\\\"video/mp4\\\"}", messageType: "media")).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(this.webhookPayload("om_interactive_all", "oc_group", "ou_1", "{\\\"elements\\\":[{\\\"tag\\\":\\\"div\\\",\\\"text\\\":{\\\"tag\\\":\\\"lark_md\\\",\\\"content\\\":\\\"interactive text\\\"}}]}", messageType: "interactive")).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(this.webhookPayload("om_merge_all", "oc_group", "ou_1", "{\\\"title\\\":\\\"merged chat\\\"}", messageType: "merge_forward")).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(this.webhookPayload("om_sticker_all", "oc_group", "ou_1", "{\\\"sticker_key\\\":\\\"stk_all\\\"}", messageType: "sticker")).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(this.webhookPayload("om_share_chat_all", "oc_group", "ou_1", "{\\\"chat_id\\\":\\\"oc_shared\\\",\\\"chat_name\\\":\\\"shared chat\\\"}", messageType: "share_chat")).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(this.webhookPayload("om_share_user_all", "oc_group", "ou_1", "{\\\"user_id\\\":\\\"ou_shared\\\",\\\"name\\\":\\\"Shared User\\\"}", messageType: "share_user")).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 12)
        for (i in 0..inbound.size) {
            @Expect(inbound[i].accountId, "work")
            @Expect(inbound[i].conversationId.getOrThrow(), "oc_group")
            @Expect(inbound[i].mediaContext.get("channel").getOrThrow().asString().getValue(), "feishu")
            @Expect(inbound[i].mediaContext.get("accountId").getOrThrow().asString().getValue(), "work")
            let route = inbound[i].mediaContext.get("context").getOrThrow().asObject()
                .get("imRoute").getOrThrow().asObject()
            @Expect(route.get("channel").getOrThrow().asString().getValue(), "feishu")
            @Expect(route.get("accountId").getOrThrow().asString().getValue(), "work")
            @Expect(route.get("peerKind").getOrThrow().asString().getValue(), "group")
            @Expect(route.get("peerId").getOrThrow().asString().getValue(), "oc_group")
            @Expect(route.get("senderId").getOrThrow().asString().getValue(), "ou_1")
            @Expect(route.get("messageId").getOrThrow().asString().getValue().startsWith("om_"), true)
            @Expect(inbound[i].text.trimAscii().isEmpty(), false)
        }
        @Expect(inbound[2].mediaContext.get("records").getOrThrow().asArray()[0].asObject().get("mediaKind").getOrThrow().asString().getValue(), "image")
        @Expect(inbound[3].mediaContext.get("records").getOrThrow().asArray()[0].asObject().get("mediaKind").getOrThrow().asString().getValue(), "file")
        @Expect(inbound[4].mediaContext.get("records").getOrThrow().asArray()[0].asObject().get("mediaKind").getOrThrow().asString().getValue(), "audio")
        @Expect(inbound[5].mediaContext.get("records").getOrThrow().asArray()[0].asObject().get("mediaKind").getOrThrow().asString().getValue(), "video")
        @Expect(inbound[6].mediaContext.get("records").getOrThrow().asArray()[0].asObject().get("mediaKind").getOrThrow().asString().getValue(), "media")
        let merge = inbound[8].mediaContext.get("context").getOrThrow().asObject().get("feishuMergeForward").getOrThrow().asObject()
        @Expect(merge.get("status").getOrThrow().asString().getValue(), "metadata_only")
        @Expect(merge.get("resourceFetch").getOrThrow().asObject().get("status").getOrThrow().asString().getValue(), "external_resource_required")
    }

    @TestCase
    public func mediaContextSeparatesCurrentHistoricalBotImageAndDocMediaBoundaries(): Unit {
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true), accountId: "work")
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_resource_boundary",
                "oc_group",
                "ou_1",
                "{\\\"image_key\\\":\\\"img_boundary\\\",\\\"file_name\\\":\\\"diagram.png\\\",\\\"mime_type\\\":\\\"image/png\\\"}",
                messageType: "image"
            )
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        let boundary = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuResourceBoundary").getOrThrow().asObject()
        let current = boundary.get("currentTurn").getOrThrow().asObject()
        let historical = boundary.get("historicalResource").getOrThrow().asObject()
        let botImage = boundary.get("botImage").getOrThrow().asObject()
        let docMedia = boundary.get("docMedia").getOrThrow().asObject()
        @Expect(current.get("relation").getOrThrow().asString().getValue(), "current")
        @Expect(current.get("status").getOrThrow().asString().getValue(), "staged_metadata")
        @Expect(historical.get("relation").getOrThrow().asString().getValue(), "historical")
        @Expect(historical.get("status").getOrThrow().asString().getValue(), "auth_required")
        @Expect(historical.get("tool").getOrThrow().asString().getValue(), "feishu_im_user_fetch_resource")
        @Expect(botImage.get("identity").getOrThrow().asString().getValue(), "bot")
        @Expect(botImage.get("status").getOrThrow().asString().getValue(), "not_configured")
        @Expect(docMedia.get("tool").getOrThrow().asString().getValue(), "feishu_doc_media")
        @Expect(docMedia.get("status").getOrThrow().asString().getValue(), "auth_required")
        @Expect(boundary.toJsonString().contains("Authorization"), false)
        @Expect(boundary.toJsonString().contains("Bearer "), false)
    }

    @TestCase
    public func videoInteractiveAndMergeForwardConvertersPreserveSafeContext(): Unit {
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true), accountId: "work")
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_video",
                "oc_group",
                "ou_1",
                "{\\\"file_key\\\":\\\"video_v2_1\\\",\\\"file_name\\\":\\\"demo.mp4\\\",\\\"mime_type\\\":\\\"video/mp4\\\"}",
                messageType: "video"
            )
        ).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_interactive",
                "oc_group",
                "ou_1",
                "{\\\"elements\\\":[{\\\"tag\\\":\\\"div\\\",\\\"text\\\":{\\\"tag\\\":\\\"lark_md\\\",\\\"content\\\":\\\"Choose option\\\"}}]}",
                messageType: "interactive"
            )
        ).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_merge",
                "oc_group",
                "ou_1",
                "{\\\"title\\\":\\\"forwarded thread\\\"}",
                messageType: "merge_forward"
            )
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 3)
        @Expect(inbound[0].text, "[video]")
        let video = inbound[0].mediaContext.get("records").getOrThrow().asArray()[0].asObject()
        @Expect(video.get("mediaKind").getOrThrow().asString().getValue(), "video")
        @Expect(video.get("eligibleFor").getOrThrow().asString().getValue(), "video")
        @Expect(inbound[1].text.contains("Choose option"), true)
        @Expect(inbound[2].text.contains("forwarded thread"), true)
        let mergeContext = inbound[2].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuMergeForward").getOrThrow().asObject()
        @Expect(mergeContext.get("title").getOrThrow().asString().getValue(), "forwarded thread")
        @Expect(mergeContext.get("status").getOrThrow().asString().getValue(), "metadata_only")
        @Expect(mergeContext.get("resourceFetch").getOrThrow().asObject().get("tool").getOrThrow().asString().getValue(), "feishu_im_message.list_forward_messages")
    }

    @TestCase
    public func quoteReactionAndMergeForwardExposeDiagnosticContext(): Unit {
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true), accountId: "work")
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_quote",
                "oc_group",
                "ou_reply",
                "{\\\"text\\\":\\\"quoted reply\\\"}",
                rootId: "om_root",
                threadId: "omt_thread"
            )
        ).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(this.reactionPayload(accountId: "work")).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_merge_diag",
                "oc_group",
                "ou_forwarder",
                "{\\\"title\\\":\\\"forwarded thread\\\",\\\"message_count\\\":2}",
                messageType: "merge_forward"
            )
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 3)
        let quoteCtx = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuQuote").getOrThrow().asObject()
        @Expect(quoteCtx.get("messageId").getOrThrow().asString().getValue(), "om_quote")
        @Expect(quoteCtx.get("rootId").getOrThrow().asString().getValue(), "om_root")
        @Expect(quoteCtx.get("threadId").getOrThrow().asString().getValue(), "omt_thread")
        @Expect(quoteCtx.get("replyTargetMessageId").getOrThrow().asString().getValue(), "om_root")
        @Expect(quoteCtx.get("status").getOrThrow().asString().getValue(), "metadata_only")

        let reaction = inbound[1].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuReaction").getOrThrow().asObject()
        @Expect(inbound[1].systemEventKind, "feishu.reaction")
        @Expect(reaction.get("status").getOrThrow().asString().getValue(), "accepted")
        @Expect(reaction.get("resourceFetch").getOrThrow().asObject().get("status").getOrThrow().asString().getValue(), "not_required")

        let merge = inbound[2].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuMergeForward").getOrThrow().asObject()
        @Expect(merge.get("title").getOrThrow().asString().getValue(), "forwarded thread")
        @Expect(merge.get("declaredMessageCount").getOrThrow().asInt().getValue(), 2)
        @Expect(merge.get("resourceFetch").getOrThrow().asObject().get("status").getOrThrow().asString().getValue(), "external_resource_required")
    }

    @TestCase
    public func richResourceLiveReadyContextExposesOperatorEvidenceAndFetchClasses(): Unit {
        let client = FeishuFakeApiClient()
        client.setResourceError(
            "work",
            "om_scope",
            "img_scope",
            "image",
            "scope_missing",
            error: "missing im:message.resource:read"
        )
        client.setResourceError(
            "work",
            "om_api",
            "file_api",
            "file",
            "api_error",
            error: "Authorization: Bearer must-not-render"
        )
        let adapter = FeishuAdapter(
            config: FeishuConfig(
                enabled: true,
                media: FeishuMediaConfig(downloadEnabled: true)
            ),
            accountId: "work",
            apiClient: client
        )
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_scope",
                "oc_group",
                "ou_image_sender",
                "{\\\"image_key\\\":\\\"img_scope\\\",\\\"file_name\\\":\\\"diagram.png\\\",\\\"mime_type\\\":\\\"image/png\\\"}",
                messageType: "image"
            )
        ).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_api",
                "oc_group",
                "ou_file_sender",
                "{\\\"file_key\\\":\\\"file_api\\\",\\\"file_name\\\":\\\"report.pdf\\\",\\\"mime_type\\\":\\\"application/pdf\\\"}",
                messageType: "file"
            )
        ).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_quote_live",
                "oc_group",
                "ou_reply",
                "{\\\"text\\\":\\\"quoted reply\\\"}",
                rootId: "om_root_live",
                threadId: "omt_live"
            )
        ).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(this.reactionPayload(accountId: "work")).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_merge_live",
                "oc_group",
                "ou_forwarder",
                "{\\\"title\\\":\\\"forwarded thread\\\",\\\"message_count\\\":2}",
                messageType: "merge_forward"
            )
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 5)
        let imageRecord = inbound[0].mediaContext.get("records").getOrThrow().asArray()[0].asObject()
        let imageCurrent = imageRecord.get("currentTurnContext").getOrThrow().asObject()
        @Expect(imageCurrent.get("relation").getOrThrow().asString().getValue(), "current")
        @Expect(imageCurrent.get("messageType").getOrThrow().asString().getValue(), "image")
        @Expect(imageCurrent.get("source").getOrThrow().asString().getValue(), "im.message.receive_v1")
        @Expect(imageCurrent.get("operatorId").getOrThrow().asString().getValue(), "ou_image_sender")
        let imageFetch = imageRecord.get("resourceFetch").getOrThrow().asObject()
        @Expect(imageFetch.get("status").getOrThrow().asString().getValue(), "scope_missing")
        @Expect(imageFetch.get("errorClass").getOrThrow().asString().getValue(), "scope_missing")
        @Expect(imageFetch.get("redacted").getOrThrow().asBool().getValue(), true)

        let fileRecord = inbound[1].mediaContext.get("records").getOrThrow().asArray()[0].asObject()
        let fileFetch = fileRecord.get("resourceFetch").getOrThrow().asObject()
        @Expect(fileFetch.get("status").getOrThrow().asString().getValue(), "api_error")
        @Expect(fileFetch.get("errorClass").getOrThrow().asString().getValue(), "api_error")
        @Expect(fileFetch.toJsonString().contains("must-not-render"), false)

        let boundary = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuResourceBoundary").getOrThrow().asObject()
        let historical = boundary.get("historicalResource").getOrThrow().asObject()
        let historicalClasses = historical.get("errorClasses").getOrThrow().asArray()
        @Expect(historical.get("status").getOrThrow().asString().getValue(), "auth_required")
        @Expect(historicalClasses[0].asString().getValue(), "auth_required")
        @Expect(historicalClasses[1].asString().getValue(), "scope_missing")
        @Expect(historicalClasses[2].asString().getValue(), "api_error")

        let quoteLive = inbound[2].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuQuote").getOrThrow().asObject()
        let quoteEvidence = quoteLive.get("operatorEvidence").getOrThrow().asObject()
        @Expect(quoteEvidence.get("operatorId").getOrThrow().asString().getValue(), "ou_reply")
        @Expect(quoteEvidence.get("operation").getOrThrow().asString().getValue(), "quote_reply")
        @Expect(quoteLive.get("historicalFetch").getOrThrow().asObject().get("status").getOrThrow().asString().getValue(), "auth_required")

        let reaction = inbound[3].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuReaction").getOrThrow().asObject()
        let reactionEvidence = reaction.get("operatorEvidence").getOrThrow().asObject()
        @Expect(reactionEvidence.get("operatorId").getOrThrow().asString().getValue(), "ou_reactor")
        @Expect(reactionEvidence.get("operation").getOrThrow().asString().getValue(), "reaction_created")
        @Expect(reactionEvidence.get("redacted").getOrThrow().asBool().getValue(), true)

        let merge = inbound[4].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuMergeForward").getOrThrow().asObject()
        let mergeEvidence = merge.get("operatorEvidence").getOrThrow().asObject()
        @Expect(mergeEvidence.get("operatorId").getOrThrow().asString().getValue(), "ou_forwarder")
        @Expect(mergeEvidence.get("operation").getOrThrow().asString().getValue(), "merge_forward")
        @Expect(merge.get("historicalFetch").getOrThrow().asObject().get("status").getOrThrow().asString().getValue(), "auth_required")
    }

    @TestCase
    public func imageResourceDownloadPersistsToConfiguredSafeTempPath(): Unit {
        let root = "/tmp/metis-feishu-media-download-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
        try { remove(Path(root), recursive: true) } catch (_e: Exception) { () }
        let client = FeishuFakeApiClient()
        client.setResource(
            "work",
            "om_image_dl",
            "img_v2_dl",
            "image",
            "fake-image".toArray(),
            contentType: "image/png",
            fileName: "diagram.png"
        )
        let adapter = FeishuAdapter(
            config: FeishuConfig(
                enabled: true,
                media: FeishuMediaConfig(downloadEnabled: true, allowedMimes: ["image/*"], downloadRoot: root)
            ),
            accountId: "work",
            apiClient: client
        )
        adapter.start()
        try {
            @Expect(adapter.ingestWebhookPayload(
                this.webhookPayload(
                    "om_image_dl",
                    "oc_group",
                    "ou_1",
                    "{\\\"image_key\\\":\\\"img_v2_dl\\\",\\\"file_name\\\":\\\"diagram.png\\\",\\\"mime_type\\\":\\\"image/png\\\"}",
                    messageType: "image"
                )
            ).contains("\"ok\":true"), true)

            let inbound = adapter.pullInbound()
            @Expect(inbound.size, 1)
            let record = inbound[0].mediaContext.get("records").getOrThrow().asArray()[0].asObject()
            @Expect(record.get("downloaded").getOrThrow().asBool().getValue(), true)
            @Expect(record.get("skippedReason").getOrThrow().asString().getValue(), "")
            let localPath = record.get("localPath").getOrThrow().asString().getValue()
            @Expect(localPath.startsWith(root), true)
            @Expect(localPath.contains(".."), false)
            @Expect(exists(Path(localPath)), true)
            @Expect(String.fromUtf8(File.readFrom(Path(localPath))), "fake-image")
        } finally {
            try { remove(Path(root), recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func imageResourceDownloadStripsTraversalFromDownloadedFileName(): Unit {
        let root = "/tmp/metis-feishu-media-safe-name-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
        try { remove(Path(root), recursive: true) } catch (_e: Exception) { () }
        let client = FeishuFakeApiClient()
        client.setResource(
            "work",
            "om_image_safe",
            "img_safe",
            "image",
            "fake-image".toArray(),
            contentType: "image/png",
            fileName: "../../diagram.png"
        )
        let adapter = FeishuAdapter(
            config: FeishuConfig(
                enabled: true,
                media: FeishuMediaConfig(downloadEnabled: true, allowedMimes: ["image/*"], downloadRoot: root)
            ),
            accountId: "work",
            apiClient: client
        )
        adapter.start()
        try {
            @Expect(adapter.ingestWebhookPayload(
                this.webhookPayload(
                    "om_image_safe",
                    "oc_group",
                    "ou_1",
                    "{\\\"image_key\\\":\\\"img_safe\\\",\\\"file_name\\\":\\\"../../diagram.png\\\",\\\"mime_type\\\":\\\"image/png\\\"}",
                    messageType: "image"
                )
            ).contains("\"ok\":true"), true)

            let inbound = adapter.pullInbound()
            let record = inbound[0].mediaContext.get("records").getOrThrow().asArray()[0].asObject()
            let localPath = record.get("localPath").getOrThrow().asString().getValue()
            @Expect(localPath.startsWith(root), true)
            @Expect(localPath.contains(".."), false)
            @Expect(exists(Path(localPath)), true)
        } finally {
            try { remove(Path(root), recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func resourceDownloadReportsPermissionAndRateLimitFailures(): Unit {
        let root = "/tmp/metis-feishu-media-errors-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
        try { remove(Path(root), recursive: true) } catch (_e: Exception) { () }
        let client = FeishuFakeApiClient()
        client.setResourceError("default", "om_forbidden", "img_forbidden", "image", "forbidden")
        client.setResourceError("default", "om_rate", "file_rate", "file", "rate_limited")
        let adapter = FeishuAdapter(
            config: FeishuConfig(
                enabled: true,
                media: FeishuMediaConfig(downloadEnabled: true, downloadRoot: root)
            ),
            apiClient: client
        )
        adapter.start()
        try {
            @Expect(adapter.ingestWebhookPayload(
                this.webhookPayload(
                    "om_forbidden",
                    "oc_group",
                    "ou_1",
                    "{\\\"image_key\\\":\\\"img_forbidden\\\",\\\"mime_type\\\":\\\"image/png\\\"}",
                    messageType: "image"
                )
            ).contains("\"ok\":true"), true)
            @Expect(adapter.ingestWebhookPayload(
                this.webhookPayload(
                    "om_rate",
                    "oc_group",
                    "ou_1",
                    "{\\\"file_key\\\":\\\"file_rate\\\",\\\"file_name\\\":\\\"rate.pdf\\\",\\\"mime_type\\\":\\\"application/pdf\\\"}",
                    messageType: "file"
                )
            ).contains("\"ok\":true"), true)

            let inbound = adapter.pullInbound()
            @Expect(inbound.size, 2)
            let forbidden = inbound[0].mediaContext.get("records").getOrThrow().asArray()[0].asObject()
            let rate = inbound[1].mediaContext.get("records").getOrThrow().asArray()[0].asObject()
            @Expect(forbidden.get("downloaded").getOrThrow().asBool().getValue(), false)
            @Expect(forbidden.get("skippedReason").getOrThrow().asString().getValue(), "forbidden")
            @Expect(rate.get("downloaded").getOrThrow().asBool().getValue(), false)
            @Expect(rate.get("skippedReason").getOrThrow().asString().getValue(), "rate_limited")
        } finally {
            try { remove(Path(root), recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func groupConfigProjectsToolPolicyAndSenderGate(): Unit {
        let groups = JsonObject()
        let group = JsonObject()
        group.put("allowFrom", JsonArray([JsonString("ou_allowed")]))
        let tools = JsonObject()
        tools.put("allow", JsonArray([JsonString("feishu_im_user_fetch_resource")]))
        group.put("tools", tools)
        groups.put("oc_team", group)
        let adapter = FeishuAdapter(
            config: FeishuConfig(
                enabled: true,
                groupPolicy: "allowlist",
                groups: Some(groups)
            )
        )
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload("om_allowed", "oc_team", "ou_allowed", "{\\\"text\\\":\\\"@bot hello\\\"}")
        ).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload("om_denied", "oc_team", "ou_other", "{\\\"text\\\":\\\"@bot hello\\\"}")
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 2)
        let route = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("imRoute").getOrThrow().asObject()
        let groupPolicy = route.get("groupPolicy").getOrThrow().asObject()
        let routeTools = groupPolicy.get("tools").getOrThrow().asObject()
        @Expect(routeTools.get("allow").getOrThrow().asArray()[0].asString().getValue(), "feishu_im_user_fetch_resource")
        let deniedGate = inbound[1].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuGate").getOrThrow().asObject()
        @Expect(deniedGate.get("triggerAgent").getOrThrow().asBool().getValue(), false)
        @Expect(deniedGate.get("reason").getOrThrow().asString().getValue(), "sender_not_allowed")
    }

    @TestCase
    public func fakeFeishuGroupPolicyReachesSessionRouteAndAgentBridgeRuntime(): Unit {
        let group = JsonObject()
        group.put("requireMention", JsonBool(false))
        group.put("systemPrompt", JsonString("group-a-only-system-prompt"))
        group.put("skills", JsonArray([JsonString("feishu-docs")]))
        let runtimePolicy = JsonObject()
        runtimePolicy.put("systemPrompt", JsonString("runtime-policy-visible"))
        group.put("runtimePolicy", runtimePolicy)
        let tools = JsonObject()
        tools.put("allow", JsonArray([JsonString("feishu_fetch_doc")]))
        group.put("tools", tools)
        let groups = JsonObject()
        groups.put("oc_bridge", group)

        let routeRoot = JsonObject()
        let agents = JsonObject()
        let list = JsonArray([])
        let mainAgent = JsonObject()
        mainAgent.put("id", JsonString("main"))
        mainAgent.put("default", JsonBool(true))
        list.add(mainAgent)
        let writer = JsonObject()
        writer.put("id", JsonString("writer"))
        list.add(writer)
        agents.put("list", list)
        routeRoot.put("agents", agents)
        let bindings = JsonArray([])
        let binding = JsonObject()
        binding.put("type", JsonString("route"))
        binding.put("agentId", JsonString("writer"))
        let matchObj = JsonObject()
        matchObj.put("channel", JsonString("feishu"))
        matchObj.put("accountId", JsonString("tenant-a"))
        let peer = JsonObject()
        peer.put("kind", JsonString("group"))
        peer.put("id", JsonString("oc_bridge"))
        matchObj.put("peer", peer)
        binding.put("match", matchObj)
        bindings.add(binding)
        routeRoot.put("bindings", bindings)

        let accounts = JsonObject()
        let tenant = JsonObject()
        tenant.put("groups", groups)
        accounts.put("tenant-a", tenant)
        let adapter = FeishuAdapter(
            config: FeishuConfig(
                enabled: true,
                accounts: Some(accounts),
                groupPolicy: "allowlist",
                requireMention: true
            )
        )
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_bridge",
                "oc_bridge",
                "ou_1",
                "{\\\"text\\\":\\\"plain group message\\\"}",
                headerAccountId: "tenant-a"
            )
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        let request = gatewaySessionRequestFromInbound(
            inbound[0],
            sessionHint: "feishu:group:oc_bridge",
            accountId: "tenant-a",
            routeRoot: routeRoot
        )
        let resolved = gatewayResolveSessionContextWithAgentRoute(request)
        let turn = resolved.turnContext
        let names = gatewayPolicyFilteredChatToolNamesForTurnContext(turn)
        let prompt = gatewayPolicyFilteredSystemPromptForTurnContext(turn, channelName: "feishu", modelName: "openai:gpt-4o-mini")

        @Expect(resolved.agentId, "writer")
        @Expect(turn.route.get("groupPolicy").isSome(), true)
        @Expect(names.contains("feishu_fetch_doc"), true)
        @Expect(names.contains("feishu_drive_file"), false)
        @Expect(prompt.contains("group-a-only-system-prompt"), true)
        @Expect(prompt.contains("runtime-policy-visible"), false)
    }

    @TestCase
    public func groupPolicyAllowlistAndBotSenderGateAreStructured(): Unit {
        let adapter = FeishuAdapter(
            config: FeishuConfig(
                enabled: true,
                groupPolicy: "allowlist",
                groupAllowFrom: ["oc_allowed"],
                allowBots: false
            )
        )
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload("om_blocked_group", "oc_blocked", "ou_1", "{\\\"text\\\":\\\"@bot hello\\\"}")
        ).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload("om_bot", "oc_allowed", "ou_bot", "{\\\"text\\\":\\\"@bot hello\\\"}")
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 2)
        let blockedGate = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuGate").getOrThrow().asObject()
        @Expect(blockedGate.get("triggerAgent").getOrThrow().asBool().getValue(), false)
        @Expect(blockedGate.get("reason").getOrThrow().asString().getValue(), "group_not_allowed")
        let botGate = inbound[1].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuGate").getOrThrow().asObject()
        @Expect(botGate.get("triggerAgent").getOrThrow().asBool().getValue(), false)
        @Expect(botGate.get("reason").getOrThrow().asString().getValue(), "bot_sender_not_allowed")
    }

    @TestCase
    public func nativeMentionEntitiesBecomeAliasCandidates(): Unit {
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true, botOpenId: "bot-open"))
        adapter.start()
        let mentions =
            "[" +
            "{\"id\":{\"open_id\":\"ou_writer\",\"user_id\":\"writer-user\"},\"name\":\"Writer\",\"key\":\"@_user_1\"}," +
            "{\"id\":{\"open_id\":\"bot-open\"},\"name\":\"Metis\",\"key\":\"@_user_bot\"}" +
            "]"
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_mentions",
                "oc_group",
                "ou_1",
                "{\\\"text\\\":\\\"please review\\\"}",
                mentions: mentions
            )
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].mentioned, true)
        let aliasCandidates = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("aliasCandidates").getOrThrow().asArray()
        @Expect(aliasCandidates.size(), 1)
        let candidate = aliasCandidates[0].asObject()
        @Expect(candidate.get("platform").getOrThrow().asString().getValue(), "feishu")
        @Expect(candidate.get("openId").getOrThrow().asString().getValue(), "ou_writer")
        @Expect(candidate.get("name").getOrThrow().asString().getValue(), "Writer")
    }

    @TestCase
    public func threadSessionRequiresFakeThreadCapableGroup(): Unit {
        let client = FeishuFakeApiClient()
        client.setThreadCapable("oc_threads", true)
        client.setThreadCapable("oc_plain", false)
        let adapter = FeishuAdapter(
            config: FeishuConfig(enabled: true, threadSession: true),
            apiClient: client
        )
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload("om_thread_ok", "oc_threads", "ou_1", "{\\\"text\\\":\\\"topic\\\"}", threadId: "omt_1")
        ).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload("om_thread_no", "oc_plain", "ou_1", "{\\\"text\\\":\\\"topic\\\"}", threadId: "omt_2")
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 2)
        @Expect(inbound[0].conversationId.getOrThrow(), "oc_threads:topic:omt_1")
        @Expect(inbound[1].conversationId.getOrThrow(), "oc_plain")
        let route = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("imRoute").getOrThrow().asObject()
        @Expect(route.get("threadSessionKey").getOrThrow().asString().getValue(), "oc_threads:topic:omt_1")
    }

    @TestCase
    public func threadSessionCachesThreadCapabilityAndReportsSkippedReason(): Unit {
        let client = FeishuFakeApiClient()
        client.setThreadCapable("oc_plain", false)
        let adapter = FeishuAdapter(
            config: FeishuConfig(enabled: true, threadSession: true),
            apiClient: client
        )
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload("om_thread_no_1", "oc_plain", "ou_1", "{\\\"text\\\":\\\"topic\\\"}", threadId: "omt_1")
        ).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload("om_thread_no_2", "oc_plain", "ou_1", "{\\\"text\\\":\\\"topic\\\"}", threadId: "omt_2")
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 2)
        @Expect(inbound[0].conversationId.getOrThrow(), "oc_plain")
        @Expect(client.threadCapabilityChecks("oc_plain"), 1)
        let route = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("imRoute").getOrThrow().asObject()
        @Expect(route.get("threadSessionKey").isNone(), true)
        let diagnostic = route.get("threadSessionDiagnostic").getOrThrow().asObject()
        @Expect(diagnostic.get("status").getOrThrow().asString().getValue(), "skipped")
        @Expect(diagnostic.get("reason").getOrThrow().asString().getValue(), "thread_not_capable")
    }

}
