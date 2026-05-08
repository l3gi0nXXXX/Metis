package metis.gateway.core

import metis.core.renderGatewayTopicEditText
import metis.core.config.{CliSettingManager, GatewayUserSettings, cliSetupVisibleModelProviders}
import metis.gateway.model.*
import metis.gateway.session.{GatewaySessionContext, gatewaySessionRequestFromInbound}
import metis.gateway.tools.{gatewayHandleNativeCommandLine, gatewayHandleSubagentsCommandLine}
import magic.jsonable.*
import magic.log.LogUtils
import std.collection.{ArrayList, HashSet}
import std.convert.Parsable
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

/**
 * GatewayService（P0）：
 * 将渠道消息处理链路串起来。
 *
 * 数据流：
 * ChannelAdapter.pullInbound()
 *   -> GatewayRouter.route()
 *   -> AgentBridge.reply()
 *   -> ChannelAdapter.send()
 */
public class GatewayService {
    private let router: GatewayRouter
    private let channelManager: GatewayChannelManager
    private let transcriptPublisher: Option<(GatewaySessionContext, Int64, String, String) -> Unit>
    private let telegramAutoTopicLabelAttempts = HashSet<String>()
    private let consumedTelegramPluginCallbackIds = HashSet<String>()
    private let telegramErrorPolicyState = GatewayTelegramErrorPolicyState()

    public init(
        router: GatewayRouter,
        transcriptPublisher!: Option<(GatewaySessionContext, Int64, String, String) -> Unit> = None<(GatewaySessionContext, Int64, String, String) -> Unit>
    ) {
        this.router = router
        this.channelManager = GatewayChannelManager()
        this.transcriptPublisher = transcriptPublisher
    }

    private func startNowMs(): Int64 {
        DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000
    }

    /**
     * 注册渠道适配器。
     * 一般在 start() 之前完成注册。
     */
    public func registerAdapter(
        adapter: ChannelAdapter,
        channelId!: String = "",
        accountId!: String = "default",
        pluginId!: String = "",
        origin!: String = "builtin",
        runtimeKind!: String = "adapter",
        compatibilityMode!: String = "native-cangjie",
        label!: String = "",
        detailLabel!: String = "",
        enabled!: Bool = true,
        configured!: Bool = true,
        healthMonitorEnabled!: Bool = true
    ): Unit {
        this.channelManager.registerAdapter(
            adapter,
            channelId: channelId,
            accountId: accountId,
            pluginId: pluginId,
            origin: origin,
            runtimeKind: runtimeKind,
            compatibilityMode: compatibilityMode,
            label: label,
            detailLabel: detailLabel,
            enabled: enabled,
            configured: configured,
            healthMonitorEnabled: healthMonitorEnabled
        )
    }

    /** 按 `ChannelAdapter.name` 查找已注册适配器（如 `feishu`、`qq`）。 */
    public func getAdapter(name: String): Option<ChannelAdapter> {
        this.channelManager.getAdapter(name)
    }

    /** 提供给 control-ui / gateway RPC 的 live channel runtime snapshot。 */
    public func liveChannelSnapshot(): JsonObject {
        this.channelManager.liveSnapshotJson()
    }

    /**
     * 启动所有已注册渠道。
     */
    public func start(): Unit {
        let startMs = this.startNowMs()
        this.channelManager.startChannels()
        let _ = gatewayOpenClawPluginSidecarStart(CliSettingManager.readGatewaySettings())
        LogUtils.info("Gateway.service.timing: step=startChannels elapsedMs=${this.startNowMs() - startMs}")
    }

    /**
     * 停止所有渠道。
     */
    public func stop(): Unit {
        let _ = gatewayOpenClawPluginSidecarStop(CliSettingManager.readGatewaySettings())
        // Gateway process shutdown should not persist a user-level manual stop.
        this.channelManager.stopChannels(reason: "shutdown", manualStop: false)
    }

    /**
     * 执行一轮消息处理循环（单次 poll）。
     * P0 用单次循环更容易调试与测试；外层可按需定时调用。
     */
    public func processOnce(): Unit {
        this.channelManager.processOnce({ message, accountId => this.handleInbound(message, accountId) })
    }

    private func handleInbound(message: InboundMessage, accountId: String): Unit {
        let effectiveAccountId = if (!message.accountId.trimAscii().isEmpty()) {
            message.accountId.trimAscii()
        } else {
            accountId.trimAscii()
        }
        LogUtils.info(
            "Gateway.inbound: channel=${channelToString(message.channel)}, account=${effectiveAccountId}, chatType=${chatTypeToString(message.chatType)}, sender=${message.senderId}, peer=${message.peerId}, text='${message.text}'"
        )
        let decision = this.router.route(message)
        LogUtils.info("Gateway.route: accepted=${decision.accepted}, reason=${decision.reason}")
        if (!decision.accepted) {
            // P0: 被拒绝消息直接忽略。后续可补审计日志与指标上报。
            return
        }

        let user = CliSettingManager.readGatewaySettings()
        var conversationKey = decision.conversationKey.getOrThrow()
        if (channelToString(message.channel) == "telegram") {
            let bindingSession = gatewayTelegramThreadBindingSessionHintForMessage(user, message, effectiveAccountId)
            if (!bindingSession.trimAscii().isEmpty()) {
                conversationKey = bindingSession.trimAscii()
                LogUtils.info("Gateway.telegram.threadBinding: peer=${message.peerId} session=${conversationKey}")
            }
        }
        if (channelToString(message.channel) == "telegram" && message.text.trimAscii().startsWith("[telegram-approval]")) {
            let result = gatewayResolveTelegramApprovalCallback(message.text, user)
            let reply = gatewayTelegramApprovalResolverReply(result)
            this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                reply,
                replyToMessageId: message.replyTargetMessageId,
                replyInThread: message.replyInThread,
                accountId: effectiveAccountId
            )
            return
        }
        if (channelToString(message.channel) == "telegram" && this.handleTelegramNativeCommand(message, effectiveAccountId, user, conversationKey)) {
            return
        }
        let request = gatewaySessionRequestFromInbound(message, sessionHint: conversationKey, accountId: effectiveAccountId)
        if (channelToString(message.channel) == "telegram") {
            this.maybeSendTelegramLifecycleSignal(user, message, effectiveAccountId, "typing")
            this.maybeSendTelegramLifecycleSignal(user, message, effectiveAccountId, "thinking")
        }
        let turn = try {
            gatewayExecuteSessionRequestTurnForUser(
                user,
                request,
                message.text,
                deliver: true,
                replyToMessageId: this.telegramReplyTargetOrMessageId(message),
                replyInThread: message.replyInThread,
                deliverHook: Some({ channelName, deliveryAccountId, peerId, text, replyToMessageId, replyInThread =>
                    let (effectiveReplyToMessageId, effectiveReplyInThread, degraded, policyReason) =
                        gatewayApplyOutboundChannelPolicy(user, channelName, replyToMessageId, replyInThread)
                    if (degraded) {
                        LogUtils.info("Gateway.send policy: channel=${channelName} peer=${peerId} degraded=true reason=${policyReason}")
                    }
                    this.sendTextToPeerDetailed(
                        channelName,
                        peerId,
                        text,
                        replyToMessageId: effectiveReplyToMessageId,
                        replyInThread: effectiveReplyInThread,
                        accountId: if (!deliveryAccountId.trimAscii().isEmpty()) { deliveryAccountId } else { effectiveAccountId }
                    )
                }),
                transcriptHook: this.transcriptPublisher
            )
        } catch (e: Exception) {
            if (channelToString(message.channel) == "telegram") {
                this.maybeSendTelegramLifecycleSignal(user, message, effectiveAccountId, "error")
                this.handleTelegramInboundExecutionError(user, message, effectiveAccountId, e)
                return
            }
            throw e
        }
        let context = turn.context
        let execution = turn.execution
        LogUtils.info("Gateway.route: conversationKey=${conversationKey}, resolvedSession=${context.sessionKey}")
        LogUtils.info("Gateway.reply: answerChars=${execution.answer.size}")
        match (context.deliveryTarget) {
            case Some(target) =>
                LogUtils.info("Gateway.send: channel=${target.channelName} peer=${target.peerId} ok")
            case None =>
                LogUtils.info("Gateway.send: delivery target missing after execution")
        }
        if (execution.delivered) {
            if (channelToString(message.channel) == "telegram") {
                this.maybeSendTelegramLifecycleSignal(user, message, effectiveAccountId, "done")
                this.maybeAutoLabelTelegramTopic(user, message, effectiveAccountId)
            }
            return
        }
        LogUtils.error("Gateway.send: deliveryStatus=${execution.deliveryStatus} err=${execution.deliveryError}")
    }

    private func maybeAutoLabelTelegramTopic(user: GatewayUserSettings, message: InboundMessage, accountId: String): Unit {
        if (!user.telegram.actions.editForumTopic) {
            return
        }
        if (!gatewayTelegramAutoTopicLabelEnabled(user)) {
            return
        }
        let threadId = match (message.threadId) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        if (threadId.isEmpty() || !message.peerId.contains(":topic:")) {
            return
        }
        let key = "${accountId}|${message.peerId}|${threadId}"
        if (this.telegramAutoTopicLabelAttempts.contains(key)) {
            return
        }
        this.telegramAutoTopicLabelAttempts.add(key)
        let title = gatewayTelegramDeterministicAutoTopicLabel(message.text)
        try {
            let _ = this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                renderGatewayTopicEditText(title),
                replyToMessageId: Some(threadId),
                replyInThread: false,
                accountId: accountId
            )
        } catch (e: Exception) {
            LogUtils.info("Telegram auto topic label skipped: ${e.message}")
        }
    }

    private func maybeSendTelegramLifecycleSignal(
        user: GatewayUserSettings,
        message: InboundMessage,
        accountId: String,
        status: String
    ): Unit {
        let target = this.telegramReplyTargetOrMessageId(message)
        if (status == "typing") {
            try {
                let _ = this.sendTextToPeerDetailed(
                    "telegram",
                    message.peerId,
                    "[chat-action]\naction=typing",
                    replyToMessageId: target,
                    replyInThread: message.replyInThread,
                    accountId: accountId
                )
            } catch (e: Exception) {
                LogUtils.info("Telegram lifecycle chat-action skipped: ${e.message}")
            }
            return
        }
        let level = user.telegram.reactionLevel.trimAscii().toAsciiLower()
        if (!user.telegram.actions.reactions || level == "off" || level == "false" || level == "disabled") {
            return
        }
        try {
            let _ = this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                "[reaction]\nstatus=${status.trimAscii()}",
                replyToMessageId: target,
                replyInThread: message.replyInThread,
                accountId: accountId
            )
        } catch (e: Exception) {
            LogUtils.info("Telegram lifecycle reaction skipped: ${e.message}")
        }
    }

    private func telegramReplyTargetOrMessageId(message: InboundMessage): Option<String> {
        match (message.replyTargetMessageId) {
            case Some(v) => Some(v)
            case None => Some(message.messageId)
        }
    }

    private func handleTelegramInboundExecutionError(
        user: GatewayUserSettings,
        message: InboundMessage,
        accountId: String,
        error: Exception
    ): Unit {
        let threadId = match (message.threadId) {
            case Some(v) => v
            case None => ""
        }
        let nowMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
        if (!this.telegramErrorPolicyState.shouldReply(
            user,
            message.peerId,
            threadId,
            "gateway-execution",
            nowMs
        )) {
            LogUtils.info("Telegram error reply suppressed by errorPolicy for peer=${message.peerId}")
            return
        }
        let reply = "Gateway agent failed: ${error.message}"
        try {
            let _ = this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                reply,
                replyToMessageId: this.telegramReplyTargetOrMessageId(message),
                replyInThread: message.replyInThread,
                accountId: accountId
            )
        } catch (sendError: Exception) {
            LogUtils.error("Telegram error reply delivery failed: ${sendError.message}")
        }
    }

    private func handleTelegramNativeCommand(message: InboundMessage, accountId: String, user: GatewayUserSettings, sessionKey: String): Bool {
        let text = message.text.trimAscii()
        if (text == "/help" || text.startsWith("/help ") ||
            text == "/status" || text.startsWith("/status ") ||
            text == "/activation" || text.startsWith("/activation ") ||
            text == "/pair" || text.startsWith("/pair ")) {
            match (gatewayHandleNativeCommandLine(text)) {
                case Some(reply) =>
                    this.sendTextToPeerDetailed(
                        "telegram",
                        message.peerId,
                        reply,
                        replyToMessageId: message.replyTargetMessageId,
                        replyInThread: message.replyInThread,
                        accountId: accountId
                    )
                    return true
                case None => ()
            }
        }
        if (text == "/commands" || text.startsWith("/commands ")) {
            this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                this.renderTelegramCommandsCommand(user),
                replyToMessageId: message.replyTargetMessageId,
                replyInThread: message.replyInThread,
                accountId: accountId
            )
            return true
        }
        if (text == "/tools" || text.startsWith("/tools ")) {
            this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                this.renderTelegramToolsCommand(user),
                replyToMessageId: message.replyTargetMessageId,
                replyInThread: message.replyInThread,
                accountId: accountId
            )
            return true
        }
        if (text == "/whoami" || text.startsWith("/whoami ")) {
            this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                this.renderTelegramWhoamiCommand(message, accountId, sessionKey),
                replyToMessageId: message.replyTargetMessageId,
                replyInThread: message.replyInThread,
                accountId: accountId
            )
            return true
        }
        if (text == "/model" || text.startsWith("/model ")) {
            this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                this.renderTelegramModelsEntry(user, sessionKey, page: this.telegramModelsPageFromCommand(text.replace("/model", "/models"))),
                replyToMessageId: message.replyTargetMessageId,
                replyInThread: message.replyInThread,
                accountId: accountId
            )
            return true
        }
        if (text == "/session" || text.startsWith("/session ")) {
            this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                this.renderTelegramCurrentSessionCommand(sessionKey),
                replyToMessageId: message.replyTargetMessageId,
                replyInThread: message.replyInThread,
                accountId: accountId
            )
            return true
        }
        if (text == "/focus" || text.startsWith("/focus ") ||
            text == "/unfocus" || text.startsWith("/unfocus ") ||
            text == "/agents" || text.startsWith("/agents ")) {
            this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                this.renderTelegramThreadBindingCommand(text, message, accountId, user, sessionKey),
                replyToMessageId: message.replyTargetMessageId,
                replyInThread: message.replyInThread,
                accountId: accountId
            )
            return true
        }
        if (text == "/new" || text.startsWith("/new ") || text == "/reset" || text.startsWith("/reset ")) {
            this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                this.renderTelegramSessionLifecycleCommand(text, sessionKey),
                replyToMessageId: message.replyTargetMessageId,
                replyInThread: message.replyInThread,
                accountId: accountId
            )
            return true
        }
        if (text == "/compact" || text.startsWith("/compact ")) {
            this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                this.renderTelegramCompactCommand(sessionKey),
                replyToMessageId: message.replyTargetMessageId,
                replyInThread: message.replyInThread,
                accountId: accountId
            )
            return true
        }
        if (text == "/think" || text.startsWith("/think ") ||
            text == "/reasoning" || text.startsWith("/reasoning ") ||
            text == "/fast" || text.startsWith("/fast ") ||
            text == "/verbose" || text.startsWith("/verbose ")) {
            this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                this.renderTelegramReasoningCommand(text, sessionKey),
                replyToMessageId: message.replyTargetMessageId,
                replyInThread: message.replyInThread,
                accountId: accountId
            )
            return true
        }
        if (text == "/subagents" || text.startsWith("/subagents ")) {
            match (gatewayHandleSubagentsCommandLine(text)) {
                case Some(reply) =>
                    this.sendTextToPeerDetailed(
                        "telegram",
                        message.peerId,
                        reply,
                        replyToMessageId: message.replyTargetMessageId,
                        replyInThread: message.replyInThread,
                        accountId: accountId
                    )
                    return true
                case None => ()
            }
        }
        if (text == "/sessions" || text.startsWith("/sessions ")) {
            this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                this.renderTelegramSessionsCommand(text),
                replyToMessageId: message.replyTargetMessageId,
                replyInThread: message.replyInThread,
                accountId: accountId
            )
            return true
        }
        if (text == "/approvals" || text.startsWith("/approvals ")) {
            this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                this.renderTelegramApprovalsCommand(),
                replyToMessageId: message.replyTargetMessageId,
                replyInThread: message.replyInThread,
                accountId: accountId
            )
            return true
        }
        if (text == "/models" || text.startsWith("/models ")) {
            this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                this.renderTelegramModelsEntry(user, sessionKey, page: this.telegramModelsPageFromCommand(text)),
                replyToMessageId: message.replyTargetMessageId,
                replyInThread: message.replyInThread,
                accountId: accountId
            )
            return true
        }
        match (this.handleTelegramPluginCommand(message, accountId, user, sessionKey)) {
            case Some(handled) => if (handled) { return true }
            case None => ()
        }
        if (text.startsWith("[telegram-callback]")) {
            let data = this.telegramNativeField(text, "data").trimAscii()
            if (data.startsWith("models:set:")) {
                let reply = this.resolveTelegramModelCallback(data, message.senderId, user, sessionKey)
                this.sendTextToPeerDetailed(
                    "telegram",
                    message.peerId,
                    reply,
                    replyToMessageId: message.replyTargetMessageId,
                    replyInThread: message.replyInThread,
                    accountId: accountId
                )
                return true
            }
            if (data.startsWith("models:page:")) {
                let reply = this.renderTelegramModelsEntry(user, sessionKey, page: this.telegramModelsPageFromCallback(data))
                this.sendTextToPeerDetailed(
                    "telegram",
                    message.peerId,
                    reply,
                    replyToMessageId: message.replyTargetMessageId,
                    replyInThread: message.replyInThread,
                    accountId: accountId
                )
                return true
            }
            if (data.startsWith("commands:help:")) {
                let reply = gatewayHandleNativeCommandLine("/help").getOrThrow()
                this.sendTextToPeerDetailed(
                    "telegram",
                    message.peerId,
                    reply,
                    replyToMessageId: message.replyTargetMessageId,
                    replyInThread: message.replyInThread,
                    accountId: accountId
                )
                return true
            }
            if (data.startsWith("sessions:")) {
                this.sendTextToPeerDetailed(
                    "telegram",
                    message.peerId,
                    this.renderTelegramSessionsCommand("/sessions list"),
                    replyToMessageId: message.replyTargetMessageId,
                    replyInThread: message.replyInThread,
                    accountId: accountId
                )
                return true
            }
            if (data.startsWith("subagents:")) {
                let reply = gatewayHandleSubagentsCommandLine("/subagents list current") ?? "{\"ok\":true,\"status\":\"ok\",\"action\":\"subagents\",\"message\":\"Telegram subagent callback was acknowledged.\"}"
                this.sendTextToPeerDetailed(
                    "telegram",
                    message.peerId,
                    reply,
                    replyToMessageId: message.replyTargetMessageId,
                    replyInThread: message.replyInThread,
                    accountId: accountId
                )
                return true
            }
            let actionType = this.telegramNativeField(text, "actionType").trimAscii()
            if (actionType == "plugin-not-applicable" || data.startsWith("plugin:") || data.startsWith("plugin-approval:")) {
                if (this.handleTelegramPluginCallback(message, accountId, user, sessionKey, data)) {
                    return true
                }
            }
            let reply = "{\"ok\":false,\"status\":\"ignored\",\"action\":\"telegram_callback\",\"reason\":\"unknown callback action\",\"data\":\"${this.telegramCallbackJsonEscape(data)}\"}"
            this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                reply,
                replyToMessageId: message.replyTargetMessageId,
                replyInThread: message.replyInThread,
                accountId: accountId
            )
            return true
        }
        false
    }

    private func telegramCallbackJsonEscape(raw: String): String {
        raw.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "")
    }

    private func renderTelegramCommandsCommand(user: GatewayUserSettings): String {
        let native = [
            "help", "status", "commands", "tools", "whoami", "models", "model", "subagents", "sessions",
            "session", "focus", "unfocus", "agents", "new", "reset", "compact", "think", "reasoning", "fast", "verbose", "approvals",
            "activation", "pair"
        ]
        let plugins = gatewayOpenClawPluginSidecarCommandCatalog(user)
        let lines = ArrayList<String>()
        lines.add("{\"ok\":true,\"status\":\"ok\",\"action\":\"commands\",\"native\":[")
        for (i in 0..native.size) {
            let suffix = if (i + 1 < native.size) { "," } else { "" }
            lines.add("\"/${native[i]}\"${suffix}")
        }
        lines.add("],\"plugin\":[")
        for (i in 0..plugins.size) {
            let row = plugins[i]
            let suffix = if (i + 1 < plugins.size) { "," } else { "" }
            lines.add("{\"command\":\"/${this.telegramCallbackJsonEscape(row[0])}\",\"description\":\"${this.telegramCallbackJsonEscape(row[1])}\"}${suffix}")
        }
        lines.add("]}")
        String.join(lines.toArray(), delimiter: "")
    }

    private func renderTelegramToolsCommand(user: GatewayUserSettings): String {
        let sidecar = gatewayOpenClawPluginSidecarHealth(user)
        let sidecarStatus = this.telegramJsonString(sidecar, "status", if (gatewayOpenClawPluginSidecarEnabled(user)) { "unknown" } else { "disabled" })
        "{\"ok\":true,\"status\":\"ok\",\"action\":\"tools\",\"toolsets\":[\"gateway_sessions\",\"telegram_media\",\"subagents\"],\"openclawPluginSidecar\":\"${this.telegramCallbackJsonEscape(sidecarStatus)}\"}"
    }

    private func renderTelegramWhoamiCommand(message: InboundMessage, accountId: String, sessionKey: String): String {
        "{\"ok\":true,\"status\":\"ok\",\"action\":\"whoami\",\"accountId\":\"${this.telegramCallbackJsonEscape(accountId)}\",\"senderId\":\"${this.telegramCallbackJsonEscape(message.senderId)}\",\"peerId\":\"${this.telegramCallbackJsonEscape(message.peerId)}\",\"sessionKey\":\"${this.telegramCallbackJsonEscape(sessionKey)}\"}"
    }

    private func renderTelegramCurrentSessionCommand(sessionKey: String): String {
        "{\"ok\":true,\"status\":\"ok\",\"action\":\"session\",\"sessionKey\":\"${this.telegramCallbackJsonEscape(sessionKey)}\",\"message\":\"Current Telegram conversation is bound to this Gateway session key.\"}"
    }

    private func renderTelegramThreadBindingCommand(
        text: String,
        message: InboundMessage,
        accountId: String,
        user: GatewayUserSettings,
        sessionKey: String
    ): String {
        if (!user.telegram.threadBindings.enabled) {
            return "{\"ok\":false,\"status\":\"disabled\",\"action\":\"thread_binding\",\"error\":\"gateway.telegram.threadBindings.enabled is false\"}"
        }
        let command = this.telegramCommandName(text)
        let conversationId = gatewayTelegramConversationIdForMessage(message)
        let parentConversationId = this.telegramParentConversationId(message.peerId, conversationId)
        let threadId = message.threadId ?? ""
        if (command == "focus") {
            let parts = text.split(" ", 2)
            let targetSession = if (parts.size > 1 && !parts[1].trimAscii().isEmpty()) {
                parts[1].trimAscii()
            } else {
                sessionKey.trimAscii()
            }
            let result = gatewayTelegramThreadBindingBind(
                "telegram",
                accountId,
                conversationId,
                targetSession,
                parentConversationId: parentConversationId,
                threadId: threadId,
                ownerId: message.senderId
            )
            let binding = match (result.get("binding")) {
                case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
                case None => JsonObject()
            }
            return "{\"ok\":${this.telegramJsonBool(result, "ok", false)},\"status\":\"${this.telegramCallbackJsonEscape(this.telegramJsonString(result, "status", "error"))}\",\"action\":\"focus\",\"conversationId\":\"${this.telegramCallbackJsonEscape(conversationId)}\",\"sessionKey\":\"${this.telegramCallbackJsonEscape(this.telegramJsonString(binding, "sessionKey", targetSession))}\"}"
        }
        if (command == "unfocus") {
            let result = gatewayTelegramThreadBindingUnbind("telegram", accountId, conversationId)
            return "{\"ok\":${this.telegramJsonBool(result, "ok", false)},\"status\":\"${this.telegramCallbackJsonEscape(this.telegramJsonString(result, "status", "not_found"))}\",\"action\":\"unfocus\",\"conversationId\":\"${this.telegramCallbackJsonEscape(conversationId)}\"}"
        }
        let rows = gatewayTelegramThreadBindingList()
        return "{\"ok\":true,\"status\":\"ok\",\"action\":\"agents\",\"conversationId\":\"${this.telegramCallbackJsonEscape(conversationId)}\",\"bindings\":${rows.toJsonString()}}"
    }

    private func renderTelegramSessionLifecycleCommand(text: String, sessionKey: String): String {
        let action = if (text.startsWith("/new")) { "new" } else { "reset" }
        "{\"ok\":true,\"status\":\"accepted\",\"action\":\"${action}\",\"sessionKey\":\"${this.telegramCallbackJsonEscape(sessionKey)}\",\"message\":\"Session lifecycle command was accepted by Telegram native command routing. Use /sessions for transcript inspection.\"}"
    }

    private func renderTelegramCompactCommand(sessionKey: String): String {
        "{\"ok\":true,\"status\":\"accepted\",\"action\":\"compact\",\"sessionKey\":\"${this.telegramCallbackJsonEscape(sessionKey)}\",\"message\":\"Session compact command was accepted by Telegram native command routing. Persistent compaction remains owned by the Gateway sessions runtime.\"}"
    }

    private func renderTelegramReasoningCommand(text: String, sessionKey: String): String {
        let command = this.telegramCommandName(text)
        let mode = if (command == "fast") {
            "fast"
        } else if (command == "verbose") {
            "verbose"
        } else {
            let parts = text.split(" ", 2)
            if (parts.size > 1 && !parts[1].trimAscii().isEmpty()) { parts[1].trimAscii() } else { "default" }
        }
        "{\"ok\":true,\"status\":\"accepted\",\"action\":\"reasoning\",\"command\":\"/${this.telegramCallbackJsonEscape(command)}\",\"mode\":\"${this.telegramCallbackJsonEscape(mode)}\",\"sessionKey\":\"${this.telegramCallbackJsonEscape(sessionKey)}\",\"message\":\"Reasoning option command was handled natively for this Telegram session.\"}"
    }

    private func telegramCommandName(text: String): String {
        let normalized = text.trimAscii()
        if (!normalized.startsWith("/")) {
            return ""
        }
        let token = normalized.split(" ", 2)[0].trimAscii()
        let withoutSlash = token[1..]
        match (withoutSlash.indexOf("@")) {
            case Some(idx) => withoutSlash[..idx].trimAscii().toAsciiLower()
            case None => withoutSlash.trimAscii().toAsciiLower()
        }
    }

    private func handleTelegramPluginCommand(
        message: InboundMessage,
        accountId: String,
        user: GatewayUserSettings,
        sessionKey: String
    ): Option<Bool> {
        let command = this.telegramCommandName(message.text)
        if (command.isEmpty()) {
            return None<Bool>
        }
        var matched = false
        for ((pluginCommand, _description) in gatewayOpenClawPluginSidecarCommandCatalog(user)) {
            if (pluginCommand.trimAscii().toAsciiLower() == command) {
                matched = true
                break
            }
        }
        if (!matched) {
            return None<Bool>
        }
        let payload = this.telegramPluginBasePayload(message, accountId, sessionKey)
        payload.put("command", JsonString(command))
        payload.put("text", JsonString(message.text))
        payload.put("commandBody", JsonString(message.text))
        var progressMessageId = ""
        try {
            progressMessageId = this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                "Running /${command}...",
                replyToMessageId: this.telegramReplyTargetOrMessageId(message),
                replyInThread: message.replyInThread,
                accountId: accountId
            )
        } catch (e: Exception) {
            LogUtils.info("Telegram plugin command progress placeholder skipped: ${e.message}")
        }
        if (!progressMessageId.trimAscii().isEmpty()) {
            payload.put("progressMessageId", JsonString(progressMessageId.trimAscii()))
        }
        let result = gatewayOpenClawPluginSidecarInvoke(user, "command.dispatch", payload)
        let handled = this.deliverTelegramPluginSidecarResult(
            message,
            accountId,
            user,
            result,
            fallbackAction: "plugin_command",
            preferEditTargetMessageId: progressMessageId
        )
        Some(handled)
    }

    private func handleTelegramPluginCallback(
        message: InboundMessage,
        accountId: String,
        user: GatewayUserSettings,
        sessionKey: String,
        data: String
    ): Bool {
        if (!gatewayOpenClawPluginSidecarEnabled(user)) {
            this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                "{\"ok\":false,\"status\":\"not_applicable\",\"action\":\"telegram_callback\",\"reason\":\"OpenClaw plugin compatibility sidecar is disabled. Enable gateway.channelsExtra.openclawPluginCompatibility.enabled to run OpenClaw plugin interactive callbacks.\"}",
                replyToMessageId: message.replyTargetMessageId,
                replyInThread: message.replyInThread,
                accountId: accountId
            )
            return true
        }
        let callbackId = this.telegramNativeField(message.text, "id").trimAscii()
        if (!callbackId.isEmpty() && this.consumedTelegramPluginCallbackIds.contains(callbackId)) {
            this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                "{\"ok\":true,\"status\":\"ignored\",\"action\":\"telegram_callback\",\"reason\":\"duplicate callback ignored\",\"callbackId\":\"${this.telegramCallbackJsonEscape(callbackId)}\"}",
                replyToMessageId: message.replyTargetMessageId,
                replyInThread: message.replyInThread,
                accountId: accountId
            )
            return true
        }
        let payload = this.telegramPluginBasePayload(message, accountId, sessionKey)
        payload.put("callbackId", JsonString(callbackId))
        payload.put("data", JsonString(data.trimAscii()))
        let callbackMessageId = this.telegramNativeField(message.text, "messageId").trimAscii()
        let callbackSenderId = this.telegramNativeField(message.text, "by").trimAscii()
        payload.put("messageId", JsonString(callbackMessageId))
        payload.put("callbackSenderId", JsonString(callbackSenderId))
        let callbackMessage = JsonObject()
        callbackMessage.put("messageId", JsonString(callbackMessageId))
        callbackMessage.put("chatId", JsonString(this.telegramCallbackChatIdFromPeer(message.peerId)))
        callbackMessage.put("messageText", JsonString(message.raw ?? message.text))
        payload.put("callbackMessage", callbackMessage)
        let method = if (data.startsWith("plugin-approval:")) { "approval.dispatch" } else { "interactive.dispatch" }
        let result = gatewayOpenClawPluginSidecarInvoke(user, method, payload)
        if (!this.telegramJsonBool(result, "matched", false)) {
            let reason = this.telegramJsonString(result, "reason", "OpenClaw plugin sidecar handler not found")
            this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                "{\"ok\":false,\"status\":\"not_found\",\"action\":\"telegram_callback\",\"reason\":\"${this.telegramCallbackJsonEscape(reason)}\",\"data\":\"${this.telegramCallbackJsonEscape(data)}\"}",
                replyToMessageId: message.replyTargetMessageId,
                replyInThread: message.replyInThread,
                accountId: accountId
            )
            return true
        }
        if (!callbackId.isEmpty()) {
            this.consumedTelegramPluginCallbackIds.add(callbackId)
        }
        this.deliverTelegramPluginSidecarResult(message, accountId, user, result, fallbackAction: "telegram_callback")
    }

    private func telegramPluginBasePayload(message: InboundMessage, accountId: String, sessionKey: String): JsonObject {
        let payload = JsonObject()
        payload.put("channel", JsonString("telegram"))
        payload.put("accountId", JsonString(accountId.trimAscii()))
        payload.put("sessionKey", JsonString(sessionKey.trimAscii()))
        let conversationId = message.conversationId ?? message.peerId
        payload.put("conversationId", JsonString(conversationId))
        payload.put("parentConversationId", JsonString(this.telegramParentConversationId(message.peerId, conversationId)))
        payload.put("peerId", JsonString(message.peerId.trimAscii()))
        payload.put("senderId", JsonString(message.senderId.trimAscii()))
        payload.put("senderUsername", JsonString(""))
        let sender = JsonObject()
        sender.put("id", JsonString(message.senderId.trimAscii()))
        sender.put("username", JsonString(""))
        payload.put("sender", sender)
        let isGroup = match (message.chatType) {
            case ChatType.Group => true
            case ChatType.Direct => false
        }
        payload.put("isGroup", isGroup.toJsonValue())
        payload.put("isForum", (message.threadId.isSome() || message.peerId.contains(":topic:")).toJsonValue())
        let auth = JsonObject()
        auth.put("isAuthorizedSender", true.toJsonValue())
        payload.put("auth", auth)
        match (message.threadId) {
            case Some(v) => payload.put("threadId", JsonString(v.trimAscii()))
            case None => payload.put("threadId", JsonString(""))
        }
        match (message.replyTargetMessageId) {
            case Some(v) => payload.put("replyTargetMessageId", JsonString(v.trimAscii()))
            case None => payload.put("replyTargetMessageId", JsonString(""))
        }
        payload.put("replyInThread", message.replyInThread.toJsonValue())
        payload
    }

    private func telegramParentConversationId(peerId: String, conversationId: String): String {
        let normalized = peerId.trimAscii()
        match (normalized.indexOf(":topic:")) {
            case Some(idx) => normalized[..idx]
            case None =>
                match (conversationId.trimAscii().indexOf(":topic:")) {
                    case Some(idx2) => conversationId.trimAscii()[..idx2]
                    case None => ""
                }
        }
    }

    private func telegramCallbackChatIdFromPeer(peerId: String): String {
        let normalized = peerId.trimAscii()
        if (normalized.startsWith("user:")) {
            return normalized["user:".size..]
        }
        if (normalized.startsWith("group:")) {
            let pure = normalized["group:".size..]
            match (pure.indexOf(":topic:")) {
                case Some(idx) => return pure[..idx]
                case None => return pure
            }
        }
        normalized
    }

    private func deliverTelegramPluginSidecarResult(
        message: InboundMessage,
        accountId: String,
        user: GatewayUserSettings,
        result: JsonObject,
        fallbackAction!: String,
        preferEditTargetMessageId!: String = ""
    ): Bool {
        if (!this.telegramJsonBool(result, "ok", false)) {
            let reason = this.telegramJsonString(result, "reason", "OpenClaw plugin sidecar error")
            this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                "{\"ok\":false,\"status\":\"error\",\"action\":\"${fallbackAction}\",\"reason\":\"${this.telegramCallbackJsonEscape(reason)}\"}",
                replyToMessageId: message.replyTargetMessageId,
                replyInThread: message.replyInThread,
                accountId: accountId
            )
            return true
        }
        this.applyTelegramPluginBindingIntents(message, accountId, user, result)
        var delivered = false
        let intents = this.telegramJsonArray(result, "intents")
        for (i in 0..intents.size()) {
            let intent = try { intents[i].asObject() } catch (_e: Exception) { JsonObject() }
            if (!preferEditTargetMessageId.trimAscii().isEmpty() && this.telegramPluginIntentShouldEditProgress(intent)) {
                intent.put("type", JsonString("edit"))
                intent.put("targetMessageId", JsonString(preferEditTargetMessageId.trimAscii()))
            }
            if (this.deliverTelegramPluginIntent(message, accountId, intent)) {
                delivered = true
            }
        }
        if (!delivered) {
            let msg = this.telegramJsonString(result, "message", "")
            let text = if (msg.trimAscii().isEmpty()) {
                "{\"ok\":true,\"status\":\"ok\",\"action\":\"${fallbackAction}\",\"message\":\"OpenClaw plugin sidecar handled the request.\"}"
            } else {
                msg
            }
            this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                text,
                replyToMessageId: message.replyTargetMessageId,
                replyInThread: message.replyInThread,
                accountId: accountId
            )
        }
        true
    }

    private func deliverTelegramPluginIntent(message: InboundMessage, accountId: String, intent: JsonObject): Bool {
        let kind = this.telegramJsonString(intent, "type", this.telegramJsonString(intent, "kind", "")).trimAscii().toAsciiLower()
        let text = this.telegramJsonString(intent, "text", "").trimAscii()
        let target = this.telegramJsonString(intent, "targetMessageId", "").trimAscii()
        let buttonSpecs = this.telegramPluginButtonSpecs(intent)
        if (kind == "reply" || kind == "send" || kind == "message") {
            if (text.isEmpty()) { return false }
            let sendText = if (buttonSpecs.isEmpty()) {
                text
            } else {
                this.renderTelegramPluginInlineKeyboardText(text, buttonSpecs)
            }
            this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                sendText,
                replyToMessageId: message.replyTargetMessageId,
                replyInThread: message.replyInThread,
                accountId: accountId
            )
            return true
        }
        if (kind == "edit") {
            if (text.isEmpty()) { return false }
            this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                "[edit]\n${text}",
                replyToMessageId: this.telegramPluginTargetMessageId(message, target),
                replyInThread: message.replyInThread,
                accountId: accountId
            )
            return true
        }
        if (kind == "editbuttons" || kind == "edit-buttons") {
            if (buttonSpecs.isEmpty()) { return false }
            this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                this.renderTelegramPluginEditButtonsText(buttonSpecs),
                replyToMessageId: this.telegramPluginTargetMessageId(message, target),
                replyInThread: message.replyInThread,
                accountId: accountId
            )
            return true
        }
        if (kind == "clearbuttons" || kind == "clear-buttons") {
            this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                "[clear-buttons]",
                replyToMessageId: this.telegramPluginTargetMessageId(message, target),
                replyInThread: message.replyInThread,
                accountId: accountId
            )
            return true
        }
        if (kind == "delete" || kind == "deletemessage") {
            this.sendTextToPeerDetailed(
                "telegram",
                message.peerId,
                "[delete]",
                replyToMessageId: this.telegramPluginTargetMessageId(message, target),
                replyInThread: message.replyInThread,
                accountId: accountId
            )
            return true
        }
        false
    }

    private func telegramPluginIntentShouldEditProgress(intent: JsonObject): Bool {
        let kind = this.telegramJsonString(intent, "type", this.telegramJsonString(intent, "kind", "")).trimAscii().toAsciiLower()
        if (!(kind == "reply" || kind == "send" || kind == "message")) {
            return false
        }
        !this.telegramJsonString(intent, "text", "").trimAscii().isEmpty()
    }

    private func applyTelegramPluginBindingIntents(
        message: InboundMessage,
        accountId: String,
        user: GatewayUserSettings,
        result: JsonObject
    ): Unit {
        if (!user.telegram.threadBindings.enabled) {
            return
        }
        let intents = this.telegramJsonArray(result, "bindingIntents")
        for (i in 0..intents.size()) {
            let intent = try { intents[i].asObject() } catch (_e: Exception) { JsonObject() }
            let kind = this.telegramJsonString(intent, "type", this.telegramJsonString(intent, "kind", "")).trimAscii().toAsciiLower()
            if (kind != "binding") {
                continue
            }
            let op = this.telegramJsonString(intent, "op", "").trimAscii().toAsciiLower()
            let channel = this.telegramJsonString(intent, "channel", "telegram").trimAscii()
            let bindingAccount = this.telegramJsonString(intent, "accountId", accountId).trimAscii()
            let conversationId = this.telegramJsonString(intent, "conversationId", gatewayTelegramConversationIdForMessage(message)).trimAscii()
            if (conversationId.isEmpty()) {
                continue
            }
            if (op == "bind") {
                let sessionKey = this.telegramJsonString(intent, "sessionKey", "").trimAscii()
                if (sessionKey.isEmpty()) {
                    continue
                }
                let _ = gatewayTelegramThreadBindingBind(
                    channel,
                    bindingAccount,
                    conversationId,
                    sessionKey,
                    parentConversationId: this.telegramJsonString(intent, "parentConversationId", this.telegramParentConversationId(message.peerId, conversationId)),
                    threadId: this.telegramJsonString(intent, "threadId", message.threadId ?? ""),
                    ownerId: this.telegramJsonString(intent, "ownerId", message.senderId),
                    ttlMs: this.telegramJsonInt(intent, "ttlMs", 0)
                )
            } else if (op == "detach" || op == "unbind") {
                let _ = gatewayTelegramThreadBindingUnbind(channel, bindingAccount, conversationId)
            } else if (op == "touch") {
                let _ = gatewayTelegramThreadBindingTouch(channel, bindingAccount, conversationId)
            }
        }
    }

    private func renderTelegramPluginInlineKeyboardText(text: String, buttonSpecs: Array<String>): String {
        let lines = ArrayList<String>()
        lines.add("[inline-keyboard]")
        lines.add("text=${text.trimAscii()}")
        for (spec in buttonSpecs) {
            if (spec == "row") {
                lines.add("row")
            } else {
                lines.add("button=${spec}")
            }
        }
        String.join(lines.toArray(), delimiter: "\n")
    }

    private func renderTelegramPluginEditButtonsText(buttonSpecs: Array<String>): String {
        let lines = ArrayList<String>()
        lines.add("[edit-buttons]")
        for (spec in buttonSpecs) {
            if (spec == "row") {
                lines.add("row")
            } else {
                lines.add("button=${spec}")
            }
        }
        String.join(lines.toArray(), delimiter: "\n")
    }

    private func telegramPluginButtonSpecs(intent: JsonObject): Array<String> {
        let specs = ArrayList<String>()
        let buttons = this.telegramJsonArray(intent, "buttons")
        for (rowValue in buttons.getItems()) {
            var addedInRow = false
            try {
                let row = rowValue.asArray()
                if (!specs.isEmpty() && row.size() > 0) {
                    specs.add("row")
                }
                for (buttonValue in row.getItems()) {
                    let spec = this.telegramPluginButtonSpec(try { buttonValue.asObject() } catch (_e: Exception) { JsonObject() })
                    if (!spec.isEmpty()) {
                        specs.add(spec)
                        addedInRow = true
                    }
                }
            } catch (_e: Exception) {
                let spec = this.telegramPluginButtonSpec(try { rowValue.asObject() } catch (_e2: Exception) { JsonObject() })
                if (!spec.isEmpty()) {
                    if (!specs.isEmpty() && !addedInRow) {
                        ()
                    }
                    specs.add(spec)
                }
            }
        }
        specs.toArray()
    }

    private func telegramPluginButtonSpec(button: JsonObject): String {
        let text = this.telegramJsonString(button, "text", "").trimAscii()
        if (text.isEmpty()) {
            return ""
        }
        let data = this.telegramJsonString(button, "callback_data", this.telegramJsonString(button, "callbackData", "")).trimAscii()
        if (!data.isEmpty()) {
            return "${text}|callback:${data}"
        }
        let url = this.telegramJsonString(button, "url", "").trimAscii()
        if (!url.isEmpty()) {
            return "${text}|url:${url}"
        }
        ""
    }

    private func telegramPluginTargetMessageId(message: InboundMessage, target: String): Option<String> {
        let t = target.trimAscii()
        if (!t.isEmpty()) {
            return Some(t)
        }
        message.replyTargetMessageId
    }

    private func telegramJsonBool(obj: JsonObject, key: String, fallback: Bool): Bool {
        match (obj.get(key)) {
            case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { fallback }
            case None => fallback
        }
    }

    private func telegramJsonString(obj: JsonObject, key: String, fallback: String): String {
        match (obj.get(key)) {
            case Some(v) =>
                try {
                    v.asString().getValue()
                } catch (_e: Exception) {
                    fallback
                }
            case None => fallback
        }
    }

    private func telegramJsonInt(obj: JsonObject, key: String, fallback: Int64): Int64 {
        match (obj.get(key)) {
            case Some(v) =>
                try {
                    Int64.parse(v.toJsonString())
                } catch (_e: Exception) {
                    fallback
                }
            case None => fallback
        }
    }

    private func telegramJsonArray(obj: JsonObject, key: String): JsonArray {
        match (obj.get(key)) {
            case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
    }

    private func renderTelegramSessionsCommand(text: String): String {
        "{\"ok\":true,\"status\":\"ok\",\"action\":\"sessions\",\"usage\":\"/sessions list | /sessions path | /sessions preview <sessionKey>\",\"message\":\"Telegram /sessions is handled natively by GatewayService. Use CLI/control-ui Gateway sessions views for full transcript details.\"}"
    }

    private func renderTelegramApprovalsCommand(): String {
        "{\"ok\":true,\"status\":\"ok\",\"action\":\"approvals\",\"message\":\"Telegram approvals are handled by native callback resolver. Use control-ui or Gateway approvals surface for the full pending approval list.\"}"
    }

    private func telegramModelsPageFromCommand(text: String): Int64 {
        let parts = text.trimAscii().split(" ")
        if (parts.size >= 2) {
            try { return Int64.parse(parts[1].trimAscii()) } catch (_e: Exception) { return 0 }
        }
        0
    }

    private func telegramModelsPageFromCallback(data: String): Int64 {
        try { Int64.parse(data["models:page:".size..].trimAscii()) } catch (_e: Exception) { 0 }
    }

    private func telegramSessionModelKey(sessionKey: String): String {
        "telegram:${sessionKey.trimAscii()}"
    }

    private func telegramCurrentModelRef(user: GatewayUserSettings, sessionKey: String): String {
        let key = this.telegramSessionModelKey(sessionKey)
        let sessionModel = user.channelModels.get(key) ?? ""
        if (!sessionModel.trimAscii().isEmpty()) {
            return sessionModel.trimAscii()
        }
        user.channelModels.get("telegram") ?? ""
    }

    private func renderTelegramModelsEntry(user: GatewayUserSettings, sessionKey: String, page!: Int64 = 0): String {
        let current = this.telegramCurrentModelRef(user, sessionKey)
        let currentText = if (current.trimAscii().isEmpty()) { "global default" } else { current.trimAscii() }
        let providers = cliSetupVisibleModelProviders()
        let pageSize: Int64 = 8
        let total = Int64(providers.size)
        let totalPages = if (total <= 0) { 1 } else { (total + pageSize - 1) / pageSize }
        var effectivePage = page
        if (effectivePage < 0) { effectivePage = 0 }
        if (effectivePage >= totalPages) { effectivePage = totalPages - 1 }
        if (!user.telegram.actions.inlineKeyboard || !user.telegram.actions.callbackQuery) {
            let lines = ArrayList<String>()
            lines.add("Telegram model")
            lines.add("Current: ${currentText}")
            lines.add("Page: ${effectivePage + 1}/${totalPages}")
            let start = effectivePage * pageSize
            let end = if (start + pageSize > total) { total } else { start + pageSize }
            for (idx in start..end) {
                let descriptor = providers[idx]
                let mark = if (descriptor.defaultModelRef == current.trimAscii()) { " *current*" } else { "" }
                lines.add("- ${descriptor.displayName}: ${descriptor.defaultModelRef}${mark}")
            }
            return String.join(lines.toArray(), delimiter: "\n")
        }
        let lines = ArrayList<String>()
        lines.add("[inline-keyboard]")
            lines.add("text=Telegram model\nCurrent: ${currentText}\nPage: ${effectivePage + 1}/${totalPages}\nSelect a model for this Telegram session.")
        let start = effectivePage * pageSize
        let end = if (start + pageSize > total) { total } else { start + pageSize }
        for (idx in start..end) {
            let descriptor = providers[idx]
            let mark = if (descriptor.defaultModelRef == current.trimAscii()) { " ✓" } else { "" }
            lines.add("button=${descriptor.displayName}${mark}|callback:models:set:${descriptor.defaultModelRef}")
        }
        if (totalPages > 1) {
            let prev = if (effectivePage <= 0) { totalPages - 1 } else { effectivePage - 1 }
            let next = if (effectivePage + 1 >= totalPages) { 0 } else { effectivePage + 1 }
            lines.add("button=Prev|callback:models:page:${prev}")
            lines.add("button=Next|callback:models:page:${next}")
        }
        String.join(lines.toArray(), delimiter: "\n")
    }

    private func resolveTelegramModelCallback(data: String, senderId: String, user: GatewayUserSettings, sessionKey: String): String {
        if (!this.telegramSenderCanOperate(senderId, user)) {
            return "Model switch denied: sender ${senderId} is not authorized."
        }
        if (!user.telegram.configWrites) {
            return "Model switch denied: gateway.telegram.configWrites is disabled."
        }
        let modelRef = data["models:set:".size..].trimAscii()
        if (modelRef.isEmpty() || modelRef.size > 48 || !modelRef.contains(":")) {
            return "Model switch failed: invalid model reference."
        }
        var next = user
        next.channelModels[this.telegramSessionModelKey(sessionKey)] = modelRef
        CliSettingManager.writeGatewaySettings(next)
        "Telegram session model switched to ${modelRef}."
    }

    private func telegramSenderCanOperate(senderId: String, user: GatewayUserSettings): Bool {
        let normalized = senderId.trimAscii()
        if (normalized.isEmpty()) {
            return false
        }
        let accepted = ["${normalized}", "tg:${normalized}", "telegram:${normalized}", "user:${normalized}"]
        for (candidate in user.telegram.allowFrom) {
            let c = candidate.trimAscii()
            if (c == "*") {
                return true
            }
            for (id in accepted) {
                if (c == id) {
                    return true
                }
            }
        }
        for (candidate in user.telegram.groupAllowFrom) {
            let c = candidate.trimAscii()
            if (c == "*") {
                return true
            }
            for (id in accepted) {
                if (c == id) {
                    return true
                }
            }
        }
        false
    }

    private func telegramNativeField(text: String, key: String): String {
        let prefix = "${key}="
        for (line in text.split("\n")) {
            let t = line.trimAscii()
            if (t.startsWith(prefix)) {
                return t[prefix.size..]
            }
        }
        ""
    }

    /**
     * 定时任务等场景：按已注册适配器名向指定 peer 发送文本（无回复线程 messageId）。
     */
    public func sendTextToPeer(
        adapterName: String,
        peerId: String,
        text: String,
        replyToMessageId!: Option<String> = None,
        replyInThread!: Bool = false,
        accountId!: String = ""
    ): Unit {
        let _ = this.sendTextToPeerDetailed(
            adapterName,
            peerId,
            text,
            replyToMessageId: replyToMessageId,
            replyInThread: replyInThread,
            accountId: accountId
        )
    }

    public func sendTextToPeerDetailed(
        adapterName: String,
        peerId: String,
        text: String,
        replyToMessageId!: Option<String> = None,
        replyInThread!: Bool = false,
        accountId!: String = ""
    ): String {
        let sendStartedAtMs = this.startNowMs()
        let nm = adapterName.trimAscii()
        let user = CliSettingManager.readGatewaySettings()
        var effectiveText = text
        if (nm.trimAscii().toAsciiLower() == "telegram" && !text.trimAscii().startsWith("[plugin-hook-cancelled]")) {
            let hook = gatewayOpenClawPluginSidecarApplyMessageSendingHook(
                user,
                nm,
                accountId,
                peerId,
                text,
                replyToMessageId ?? "",
                replyInThread
            )
            if (this.telegramJsonBool(hook, "cancelled", false)) {
                let reason = this.telegramJsonString(hook, "reason", "cancelled by OpenClaw plugin hook")
                let _ = gatewayOpenClawPluginSidecarApplyMessageSentHook(
                    user,
                    nm,
                    accountId,
                    peerId,
                    text,
                    "",
                    false,
                    reason,
                    durationMs: this.startNowMs() - sendStartedAtMs
                )
                LogUtils.info("Gateway.sendTextToPeer: channel=${nm} peer=${peerId} cancelled by OpenClaw plugin hook")
                return ""
            } else {
                let modified = this.telegramJsonString(hook, "text", text)
                if (!modified.trimAscii().isEmpty()) {
                    effectiveText = modified
                }
            }
        }
        let (effectiveReplyToMessageId, effectiveReplyInThread, degraded, policyReason) =
            gatewayApplyOutboundChannelPolicy(user, nm, replyToMessageId, replyInThread)
        if (degraded) {
            LogUtils.info("Gateway.sendTextToPeer policy: channel=${nm} peer=${peerId} degraded=true reason=${policyReason}")
        }
        let outbound = OutboundMessage(
            channelTypeFromAdapterName(nm),
            peerId,
            effectiveText,
            replyToMessageId: effectiveReplyToMessageId,
            replyInThread: effectiveReplyInThread,
            accountId: accountId
        )
        match (this.channelManager.getAdapter(nm)) {
            case Some(adapter) =>
                let sentMessageId = adapter.sendWithMessageId(outbound)
                if (!sentMessageId.trimAscii().isEmpty()) {
                    let _ = gatewayOpenClawPluginSidecarApplyMessageSentHook(
                        user,
                        nm,
                        accountId,
                        peerId,
                        effectiveText,
                        sentMessageId,
                        true,
                        "",
                        durationMs: this.startNowMs() - sendStartedAtMs
                    )
                    LogUtils.info("Gateway.sendTextToPeer: channel=${nm} peer=${peerId} ok")
                    return sentMessageId
                }
            case None => ()
        }
        let send = this.channelManager.sendToAdapterName(nm, outbound)
        if (send.delivered) {
            let _ = gatewayOpenClawPluginSidecarApplyMessageSentHook(
                user,
                nm,
                accountId,
                peerId,
                effectiveText,
                send.messageId,
                true,
                "",
                durationMs: this.startNowMs() - sendStartedAtMs
            )
            LogUtils.info("Gateway.sendTextToPeer: channel=${nm} peer=${peerId} ok")
            return send.messageId
        }
        let _ = gatewayOpenClawPluginSidecarApplyMessageSentHook(
            user,
            nm,
            accountId,
            peerId,
            effectiveText,
            "",
            false,
            send.lastReason,
            durationMs: this.startNowMs() - sendStartedAtMs
        )
        LogUtils.error("Gateway.sendTextToPeer: no adapter for channel='${nm}' peer=${peerId} lastReason=${send.lastReason}")
        throw Exception("no adapter for channel='${nm}' peer=${peerId} lastReason=${send.lastReason}")
    }
}
