package metis.gateway.core

import metis.core.renderGatewayTopicEditText
import metis.core.config.{CliConfig, CliSettingManager, GatewayUserSettings, MetisConfigManager, cliFindModelAuthChoicesForProvider, cliSetupVisibleModelProviders}
import metis.gateway.model.*
import metis.gateway.session.{GatewaySessionContext, gatewayResolveSessionContext, gatewaySessionRequestFromInbound}
import metis.gateway.tools.{gatewayHandleNativeCommandLine, gatewayHandleSubagentsCommandLine}
import magic.jsonable.*
import magic.log.LogUtils
import std.collection.{ArrayList, HashSet}
import std.convert.Parsable
import std.fs.{Directory, File, Path, copy, exists, remove}
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
    private let telegramNativeCommandRuntime = GatewayTelegramNativeCommandRuntime()

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
        if (message.systemEvent) {
            this.handleInboundSystemEvent(message, effectiveAccountId, user, conversationKey)
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

    private func handleInboundSystemEvent(message: InboundMessage, accountId: String, user: GatewayUserSettings, conversationKey: String): Unit {
        let request = gatewaySessionRequestFromInbound(message, sessionHint: conversationKey, accountId: accountId)
        let context = gatewayResolveSessionContext(request)
        let store = gatewaySessionStoreForResolvedRequest(user, request)
        let kind = if (message.systemEventKind.trimAscii().isEmpty()) { "system" } else { message.systemEventKind.trimAscii() }
        let text = if (message.text.trimAscii().isEmpty()) {
            "Gateway system event: ${kind}"
        } else {
            message.text.trimAscii()
        }
        match (context.deliveryTarget) {
            case Some(target) => store.appendBindingSnapshot(context.sessionKey, target, mode: "system-event")
            case None => ()
        }
        store.appendTranscriptEntry(context.sessionKey, "system", text)
        match (this.transcriptPublisher) {
            case Some(notify) => notify(context, 1, kind, "system")
            case None => ()
        }
        LogUtils.info("Gateway.systemEvent: channel=${channelToString(message.channel)} session=${context.sessionKey} kind=${kind}")
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
        let nativeDecision = this.telegramNativeCommandRuntime.resolveText(
            text,
            message.senderId,
            accountId,
            sessionKey,
            this.telegramSenderCanOperate(message.senderId, user)
        )
        if (this.deliverTelegramNativeRuntimeDecision(nativeDecision, message, accountId, user, sessionKey)) {
            return true
        }
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
            let modelArg = if (text.startsWith("/model ")) { text["/model ".size..].trimAscii() } else { "" }
            let reply = if (modelArg.isEmpty()) {
                this.renderTelegramModelsEntry(user, sessionKey, commandText: "/models")
            } else {
                this.applyTelegramModelSelection(modelArg, message.senderId, user, sessionKey)
            }
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
                this.renderTelegramSessionLifecycleCommand(text, user, sessionKey),
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
                this.renderTelegramCompactCommand(user, sessionKey),
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
                this.renderTelegramModelsEntry(user, sessionKey, commandText: text),
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
            if (data.startsWith("cmd:")) {
                let decision = this.telegramNativeCommandRuntime.resolveCallbackData(
                    data,
                    message.senderId,
                    accountId,
                    sessionKey,
                    this.telegramSenderCanOperate(message.senderId, user)
                )
                if (this.deliverTelegramNativeRuntimeDecision(decision, message, accountId, user, sessionKey)) {
                    return true
                }
            }
            if (data.startsWith("models:set:") || data.startsWith("models:setidx:")) {
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
            if (data == "models:providers" || data.startsWith("models:page:")) {
                let reply = this.renderTelegramModelsEntry(user, sessionKey, commandText: "/models")
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
            if (data.startsWith("models:list:")) {
                let parts = data.split(":")
                let provider = if (parts.size >= 3) { parts[2] } else { "" }
                let page = if (parts.size >= 4) { try { Int64.parse(parts[3].trimAscii()) } catch (_e: Exception) { 1 } } else { 1 }
                let reply = this.renderTelegramModelsEntry(user, sessionKey, callbackProvider: provider, callbackPage: page)
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

    private func deliverTelegramNativeRuntimeDecision(
        decision: GatewayTelegramNativeCommandDecision,
        message: InboundMessage,
        accountId: String,
        user: GatewayUserSettings,
        sessionKey: String
    ): Bool {
        if (!decision.handled) {
            return false
        }
        let reply = if (!decision.preflightReply.trimAscii().isEmpty()) {
            decision.preflightReply
        } else {
            let context = decision.context.getOrThrow()
            this.renderTelegramCatalogCommand(context.spec, context.commandText, message, accountId, user, sessionKey)
        }
        this.sendTextToPeerDetailed(
            "telegram",
            message.peerId,
            reply,
            replyToMessageId: message.replyTargetMessageId,
            replyInThread: message.replyInThread,
            accountId: accountId
        )
        true
    }

    private func telegramCallbackJsonEscape(raw: String): String {
        raw.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "")
    }

    private func telegramCommandArgText(text: String): String {
        let parts = text.trimAscii().split(" ", 2)
        if (parts.size > 1) { parts[1].trimAscii() } else { "" }
    }

    private func telegramCommandJson(action: String, status: String, ok!: Bool = true, message!: String = ""): JsonObject {
        let out = JsonObject()
        out.put("ok", ok.toJsonValue())
        out.put("status", JsonString(status))
        out.put("action", JsonString(action))
        if (!message.trimAscii().isEmpty()) {
            out.put("message", JsonString(message.trimAscii()))
        }
        out
    }

    private func renderTelegramCatalogCommand(
        spec: GatewayTelegramNativeCommandSpec,
        text: String,
        message: InboundMessage,
        accountId: String,
        user: GatewayUserSettings,
        sessionKey: String
    ): String {
        if ((spec.auth == "operator" || spec.auth == "approval") && !this.telegramSenderCanOperate(message.senderId, user)) {
            let denied = this.telegramCommandJson(spec.command, "rejected", ok: false, message: "sender is not authorized for /${spec.command}")
            denied.put("auth", JsonString(spec.auth))
            denied.put("senderId", JsonString(message.senderId))
            return denied.toJsonString()
        }
        if (spec.status == "not_applicable") {
            let out = this.telegramCommandJson(spec.command, "not_applicable", ok: false, message: spec.notApplicableReason)
            out.put("category", JsonString(spec.category))
            return out.toJsonString()
        }
        if (spec.status == "approval_required") {
            let out = this.telegramCommandJson(spec.command, "approval_required", ok: false, message: spec.notApplicableReason)
            out.put("category", JsonString(spec.category))
            return out.toJsonString()
        }
        if (this.shouldRenderTelegramArgsMenu(spec, text, user)) {
            return this.renderTelegramArgsMenu(spec)
        }
        match (spec.command) {
            case "help" | "status" | "activation" | "pair" => gatewayHandleNativeCommandLine("/${spec.command} ${this.telegramCommandArgText(text)}").getOrThrow()
            case "commands" => this.renderTelegramCommandsCommand(user)
            case "tools" => this.renderTelegramToolsCommand(user)
            case "whoami" => this.renderTelegramWhoamiCommand(message, accountId, sessionKey)
            case "model" =>
                let modelArg = this.telegramCommandArgText(text)
                if (modelArg.isEmpty()) {
                    this.renderTelegramModelsEntry(user, sessionKey, commandText: "/models")
                } else {
                    this.applyTelegramModelSelection(modelArg, message.senderId, user, sessionKey)
                }
            case "models" => this.renderTelegramModelsEntry(user, sessionKey, commandText: text)
            case "allowlist" => gatewayTelegramRenderAllowlistCommand(text, user, accountId, message.senderId)
            case "session" => this.renderTelegramCurrentSessionCommand(sessionKey)
            case "sessions" => gatewayTelegramRenderSessionsCommand(text, user)
            case "approvals" => gatewayTelegramRenderApprovalsCommand()
            case "focus" | "unfocus" | "agents" => this.renderTelegramThreadBindingCommand(text, message, accountId, user, sessionKey)
            case "subagents" => gatewayHandleSubagentsCommandLine(text) ?? this.renderTelegramSubagentsFallback(text)
            case "new" | "reset" => this.renderTelegramSessionLifecycleCommand(text, user, sessionKey)
            case "compact" => this.renderTelegramCompactCommand(user, sessionKey)
            case "think" | "reasoning" | "fast" | "verbose" | "send" | "usage" | "queue" | "elevated" | "exec" => this.renderTelegramSessionOptionCommand(spec.command, text, user, sessionKey)
            case "tasks" => this.renderTelegramTasksCommand(user, sessionKey)
            case "context" => this.renderTelegramContextCommand(message, accountId, sessionKey)
            case "plugins" => this.renderTelegramPluginsCommand(text, user, message.senderId)
            case "mcp" => this.renderTelegramMcpCommand(text, user, message.senderId)
            case "config" => this.renderTelegramConfigCommand(text, user, message.senderId)
            case "debug" => this.renderTelegramDebugCommand(text, user, message.senderId)
            case "export-session" => this.renderTelegramExportSessionCommand(text, user, sessionKey)
            case "stop" => gatewayTelegramRenderStopCommand(user, sessionKey)
            case "kill" => gatewayHandleSubagentsCommandLine("/subagents kill ${this.telegramCommandArgText(text)}") ?? this.renderTelegramSubagentsFallback(text)
            case "steer" => gatewayHandleSubagentsCommandLine("/subagents steer ${this.telegramCommandArgText(text)}") ?? this.renderTelegramSubagentsFallback(text)
            case "approve" => this.renderTelegramApproveCommand(text, user, message.senderId)
            case "restart" => gatewayTelegramRenderRestartCommand(text, message.senderId)
            case "bash" => gatewayTelegramRenderBashCommand(text, message.senderId)
            case "skill" => gatewayTelegramRenderSkillCommand(text)
            case "btw" => gatewayTelegramRenderBtwCommand(text, sessionKey)
            case "tts" => gatewayTelegramRenderTtsCommand(text, user)
            case _ => this.telegramCommandJson(spec.command, "not_supported", ok: false, message: "No Metis Telegram native handler is registered for this catalog entry.").toJsonString()
        }
    }

    private func shouldRenderTelegramArgsMenu(spec: GatewayTelegramNativeCommandSpec, text: String, user: GatewayUserSettings): Bool {
        !spec.argsMenuChoices.isEmpty() &&
            user.telegram.actions.inlineKeyboard &&
            user.telegram.actions.callbackQuery &&
            this.telegramCommandArgText(text).isEmpty()
    }

    private func renderTelegramArgsMenu(spec: GatewayTelegramNativeCommandSpec): String {
        let lines = ArrayList<String>()
        let argName = if (spec.args.isEmpty()) { "option" } else { spec.args[0] }
        lines.add("[inline-keyboard]")
        lines.add("text=Choose ${argName} for /${spec.command}.")
        for (choice in spec.argsMenuChoices) {
            let data = this.telegramCommandCallbackData(spec.command, choice)
            if (!data.isEmpty()) {
                lines.add("button=${choice}|callback:${data}")
            }
        }
        String.join(lines.toArray(), delimiter: "\n")
    }

    private func telegramCommandCallbackData(command: String, value: String): String {
        let data = "cmd:${command.trimAscii()}:${value.trimAscii()}"
        if (data.size > 64) { "" } else { data }
    }

    private func renderTelegramNativeCommandCallback(data: String, message: InboundMessage, accountId: String, user: GatewayUserSettings, sessionKey: String): String {
        let parts = data.split(":")
        if (parts.size < 3) {
            return this.telegramCommandJson("telegram_callback", "error", ok: false, message: "invalid native command callback").toJsonString()
        }
        let command = parts[1].trimAscii()
        let value = parts[2].trimAscii()
        match (gatewayFindTelegramNativeCommandSpec(command)) {
            case Some(spec) => this.renderTelegramCatalogCommand(spec, "/${command} ${value}", message, accountId, user, sessionKey)
            case None => this.telegramCommandJson("telegram_callback", "not_found", ok: false, message: "native command callback target not found").toJsonString()
        }
    }

    private func renderTelegramCommandsCommand(user: GatewayUserSettings): String {
        let plugins = gatewayOpenClawPluginSidecarCommandCatalog(user)
        let native = JsonArray([])
        for (entry in gatewayTelegramNativeCommandCatalog()) {
            let row = JsonObject()
            row.put("command", JsonString("/${entry.command}"))
            row.put("status", JsonString(entry.status))
            row.put("category", JsonString(entry.category))
            row.put("auth", JsonString(entry.auth))
            row.put("description", JsonString(entry.description))
            if (!entry.notApplicableReason.trimAscii().isEmpty()) {
                row.put("reason", JsonString(entry.notApplicableReason))
            }
            native.add(row)
        }
        let pluginRows = JsonArray([])
        for (i in 0..plugins.size) {
            let row = plugins[i]
            let item = JsonObject()
            item.put("command", JsonString("/${row[0]}"))
            item.put("description", JsonString(row[1]))
            item.put("status", JsonString("implemented"))
            pluginRows.add(item)
        }
        let out = this.telegramCommandJson("commands", "ok")
        out.put("native", native)
        out.put("plugin", pluginRows)
        out.toJsonString()
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

    private func renderTelegramSessionLifecycleCommand(text: String, user: GatewayUserSettings, sessionKey: String): String {
        let action = if (text.startsWith("/new")) { "new" } else { "reset" }
        let store = gatewaySessionStoreForUser(user)
        let transcript = store.transcriptPath(sessionKey)
        var archived = ""
        if (exists(transcript)) {
            archived = transcript.parent.join("${transcript.fileName}.${action}.${DateTime.now().toUnixTimeStamp().toMilliseconds()}.bak").toString()
            try {
                copy(transcript, to: Path(archived), overwrite: false)
                remove(transcript)
            } catch (_e: Exception) {
                return this.telegramCommandJson(action, "error", ok: false, message: "failed to archive current session transcript").toJsonString()
            }
        }
        try {
            File.writeTo(transcript, "{\"kind\":\"meta\",\"sessionKey\":\"${this.telegramCallbackJsonEscape(sessionKey)}\",\"resetReason\":\"${action}\"}\n".toArray())
            let _ = store.listSessionKeys()
        } catch (_e: Exception) {
            return this.telegramCommandJson(action, "error", ok: false, message: "failed to create session boundary").toJsonString()
        }
        let out = this.telegramCommandJson(action, "ok", message: "session transcript boundary created")
        out.put("sessionKey", JsonString(sessionKey))
        if (!archived.isEmpty()) {
            out.put("archived", JsonString(archived))
        }
        out.toJsonString()
    }

    private func renderTelegramCompactCommand(user: GatewayUserSettings, sessionKey: String): String {
        let store = gatewaySessionStoreForUser(user)
        let transcript = store.transcriptPath(sessionKey)
        let out = this.telegramCommandJson("compact", "ok")
        out.put("sessionKey", JsonString(sessionKey))
        if (!exists(transcript)) {
            out.put("compacted", false.toJsonValue())
            out.put("reason", JsonString("no transcript"))
            return out.toJsonString()
        }
        let raw = try { String.fromUtf8(File.readFrom(transcript)) } catch (_e: Exception) { "" }
        let linesRaw = raw.split("\n")
        let lines = ArrayList<String>()
        for (line in linesRaw) {
            if (!line.trimAscii().isEmpty()) {
                lines.add(line)
            }
        }
        let maxLines: Int64 = 400
        if (lines.size <= maxLines) {
            out.put("compacted", false.toJsonValue())
            out.put("kept", Int64(lines.size).toJsonValue())
            return out.toJsonString()
        }
        let archived = transcript.parent.join("${transcript.fileName}.compact.${DateTime.now().toUnixTimeStamp().toMilliseconds()}.bak")
        try {
            copy(transcript, to: archived, overwrite: false)
            let kept = lines.toArray()[lines.size - maxLines..lines.size]
            File.writeTo(transcript, (String.join(kept, delimiter: "\n") + "\n").toArray())
            out.put("compacted", true.toJsonValue())
            out.put("kept", maxLines.toJsonValue())
            out.put("archived", JsonString(archived.toString()))
        } catch (_e: Exception) {
            out.put("ok", false.toJsonValue())
            out.put("status", JsonString("error"))
            out.put("reason", JsonString("compact failed"))
        }
        out.toJsonString()
    }

    private func renderTelegramReasoningCommand(text: String, sessionKey: String): String {
        this.renderTelegramSessionOptionCommand(this.telegramCommandName(text), text, CliSettingManager.readGatewaySettings(), sessionKey)
    }

    private func renderTelegramSessionOptionCommand(command: String, text: String, user: GatewayUserSettings, sessionKey: String): String {
        let modeRaw = this.telegramCommandArgText(text)
        let mode = if (modeRaw.isEmpty()) { "status" } else { modeRaw }
        let field = match (command) {
            case "verbose" => "verboseLevel"
            case "usage" => "responseUsage"
            case "fast" => "fastMode"
            case "send" => "sendPolicy"
            case "think" => "thinkingLevel"
            case "reasoning" => "reasoningVisibility"
            case "queue" => "queueMode"
            case "elevated" => "elevatedMode"
            case "exec" => "execDefault"
            case _ => "runtimeOption"
        }
        if (mode == "status") {
            return this.renderTelegramSessionOptionStatus(command, field, user, sessionKey)
        }
        this.patchTelegramSessionIndex(user, sessionKey, field, mode)
        let out = this.telegramCommandJson(command, "ok", message: "session runtime option updated")
        out.put("field", JsonString(field))
        out.put("mode", JsonString(mode))
        out.put("sessionKey", JsonString(sessionKey))
        out.toJsonString()
    }

    private func renderTelegramSessionOptionStatus(command: String, field: String, user: GatewayUserSettings, sessionKey: String): String {
        let store = gatewaySessionStoreForUser(user)
        let indexRoot = store.readSessionsIndexRoot()
        let entry = match (indexRoot.get(sessionKey)) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let out = this.telegramCommandJson(command, "ok")
        out.put("sessionKey", JsonString(sessionKey))
        out.put("field", JsonString(field))
        match (entry.get(field)) {
            case Some(v) => out.put("value", v)
            case None => out.put("value", JsonString(""))
        }
        out.toJsonString()
    }

    private func patchTelegramSessionIndex(user: GatewayUserSettings, sessionKey: String, field: String, value: String): Unit {
        let store = gatewaySessionStoreForUser(user)
        if (!exists(store.sessionsRoot())) {
            Directory.create(store.sessionsRoot(), recursive: true)
        }
        let indexRoot = store.readSessionsIndexRoot()
        let entry = match (indexRoot.get(sessionKey)) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        entry.put("sessionKey", JsonString(sessionKey))
        entry.put("updatedAt", DateTime.now().toUnixTimeStamp().toMilliseconds().toJsonValue())
        if (field == "fastMode") {
            let normalized = value.trimAscii().toAsciiLower()
            entry.put(field, (normalized == "on" || normalized == "true").toJsonValue())
        } else {
            entry.put(field, JsonString(value.trimAscii()))
        }
        indexRoot.put(sessionKey, entry)
        try {
            File.writeTo(store.sessionsRoot().join("sessions.json"), indexRoot.toJsonString().toArray())
        } catch (e: Exception) {
            LogUtils.error("Telegram native command failed to persist session option: ${e.message}")
        }
    }

    private func renderTelegramTasksCommand(user: GatewayUserSettings, sessionKey: String): String {
        let rows = gatewayListSessionCatalogRowsForUser(user)
        let out = this.telegramCommandJson("tasks", "ok")
        out.put("sessionKey", JsonString(sessionKey))
        out.put("sessionCount", Int64(rows.size).toJsonValue())
        out.put("message", JsonString("Metis native tasks are represented by persisted Gateway sessions and subagent runs."))
        out.toJsonString()
    }

    private func renderTelegramContextCommand(message: InboundMessage, accountId: String, sessionKey: String): String {
        let out = this.telegramCommandJson("context", "ok")
        out.put("accountId", JsonString(accountId))
        out.put("sessionKey", JsonString(sessionKey))
        out.put("peerId", JsonString(message.peerId))
        out.put("senderId", JsonString(message.senderId))
        out.put("chatType", JsonString(chatTypeToString(message.chatType)))
        out.put("message", JsonString("Telegram native commands bypass the model; normal messages use Gateway session context, media context, reply/thread metadata, and channel policy."))
        out.toJsonString()
    }

    private func renderTelegramPluginsCommand(text: String, user: GatewayUserSettings, senderId: String): String {
        let action = this.telegramCommandArgText(text).split(" ")[0].trimAscii().toAsciiLower()
        let out = this.telegramCommandJson("plugins", "ok")
        out.put("requested", JsonString(if (action.isEmpty()) { "list" } else { action }))
        if (action == "enable" || action == "disable") {
            return gatewayTelegramRenderConfigMutationApproval("plugins", text, senderId, "Plugin enable/disable is not applied directly from Telegram.")
        }
        out.put("health", gatewayOpenClawPluginSidecarHealth(user))
        let rows = JsonArray([])
        for ((command, description) in gatewayOpenClawPluginSidecarCommandCatalog(user)) {
            let row = JsonObject()
            row.put("command", JsonString(command))
            row.put("description", JsonString(description))
            rows.add(row)
        }
        out.put("commands", rows)
        out.toJsonString()
    }

    private func currentMetisRoot(): JsonObject {
        MetisConfigManager.initializeIfMissing()
        match (MetisConfigManager.rawConfig()) {
            case Some(root) => root
            case None => JsonObject()
        }
    }

    private func renderTelegramMcpCommand(text: String, _user: GatewayUserSettings, senderId: String): String {
        let args = this.telegramCommandArgText(text).split(" ", 3)
        let action = if (args.size > 0 && !args[0].trimAscii().isEmpty()) { args[0].trimAscii().toAsciiLower() } else { "show" }
        let out = this.telegramCommandJson("mcp", "ok")
        out.put("requested", JsonString(action))
        let root = this.currentMetisRoot()
        if (action == "show" || action == "get") {
            match (root.get("mcpServers")) {
                case Some(v) => out.put("mcpServers", v)
                case None => out.put("mcpServers", JsonObject())
            }
            return out.toJsonString()
        }
        gatewayTelegramRenderConfigMutationApproval("mcp", text, senderId, "/mcp set/unset is a config mutation and must use the Gateway approval surface.")
    }

    private func renderTelegramConfigCommand(text: String, user: GatewayUserSettings, senderId: String): String {
        let args = this.telegramCommandArgText(text).split(" ", 3)
        let action = if (args.size > 0 && !args[0].trimAscii().isEmpty()) { args[0].trimAscii().toAsciiLower() } else { "show" }
        let out = this.telegramCommandJson("config", "ok")
        out.put("requested", JsonString(action))
        out.put("path", JsonString(MetisConfigManager.configPath().toString()))
        if (action == "show") {
            out.put("keys", JsonString("agents,gateway,session,skills,tools,models,auth,channels,plugins,wizard,meta"))
            return out.toJsonString()
        }
        if (action == "get") {
            let path = if (args.size > 1) { args[1].trimAscii() } else { "" }
            out.put("configPath", JsonString(path))
            out.put("value", JsonString(this.telegramConfigPathValue(path)))
            return out.toJsonString()
        }
        if (!user.telegram.configWrites) {
            out.put("ok", false.toJsonValue())
            out.put("status", JsonString("rejected"))
            out.put("message", JsonString("gateway.telegram.configWrites is disabled."))
            return out.toJsonString()
        }
        gatewayTelegramRenderConfigMutationApproval("config", text, senderId, "/config set/unset is intentionally not applied from Telegram without the Gateway approval path.")
    }

    private func telegramConfigPathValue(path: String): String {
        let normalized = path.trimAscii()
        if (normalized.isEmpty()) {
            return ""
        }
        let lower = normalized.toAsciiLower()
        if (lower.contains("token") || lower.contains("secret") || lower.contains("password") || lower.contains("apikey") || lower.contains("api_key")) {
            return "<redacted>"
        }
        var current = this.currentMetisRoot()
        let parts = normalized.split(".")
        var idx: Int64 = 0
        while (idx < parts.size) {
            let key = parts[idx].trimAscii()
            match (current.get(key)) {
                case Some(v) =>
                    if (idx + 1 == parts.size) {
                        return v.toJsonString()
                    }
                    try {
                        current = v.asObject()
                    } catch (_e: Exception) {
                        return ""
                    }
                case None => return ""
            }
            idx += 1
        }
        ""
    }

    private func renderTelegramDebugCommand(text: String, _user: GatewayUserSettings, senderId: String): String {
        let action = this.telegramCommandArgText(text).split(" ")[0].trimAscii().toAsciiLower()
        if (action == "set" || action == "unset" || action == "reset") {
            return gatewayTelegramRenderConfigMutationApproval("debug", text, senderId, "Debug mutations require the Gateway approval surface.")
        }
        let out = this.telegramCommandJson("debug", if (action == "set" || action == "unset" || action == "reset") { "approval_required" } else { "ok" }, ok: !(action == "set" || action == "unset" || action == "reset"))
        out.put("configPath", JsonString(MetisConfigManager.configPath().toString()))
        out.put("message", JsonString(if (out.get("ok").getOrThrow().asBool().getValue()) { "Debug overrides are read-only from Telegram." } else { "Debug mutations require the Gateway control approval surface." }))
        out.toJsonString()
    }

    private func renderTelegramExportSessionCommand(text: String, user: GatewayUserSettings, sessionKey: String): String {
        let requested = this.telegramCommandArgText(text)
        let exportDir = CliConfig.dotDir.join("exports")
        if (!exists(exportDir)) {
            Directory.create(exportDir, recursive: true)
        }
        let target = if (requested.isEmpty()) {
            exportDir.join("${sessionKey.replace(":", "_")}.html")
        } else {
            let p = Path(requested)
            if (p.toString().startsWith(exportDir.toString())) { p } else { exportDir.join(p.fileName) }
        }
        let store = gatewaySessionStoreForUser(user)
        let raw = match (store.readTranscriptRaw(sessionKey)) {
            case Some(v) => v
            case None => ""
        }
        File.writeTo(target, ("<html><body><pre>" + this.telegramCallbackJsonEscape(raw) + "</pre></body></html>").toArray())
        let out = this.telegramCommandJson("export-session", "ok", message: "session exported")
        out.put("path", JsonString(target.toString()))
        out.put("sessionKey", JsonString(sessionKey))
        out.toJsonString()
    }

    private func renderTelegramStopCommand(sessionKey: String): String {
        let out = this.telegramCommandJson("stop", "no_active_run", message: "No active Gateway run is tracked for this Telegram session.")
        out.put("sessionKey", JsonString(sessionKey))
        out.toJsonString()
    }

    private func renderTelegramApproveCommand(text: String, user: GatewayUserSettings, senderId: String): String {
        let args = this.telegramCommandArgText(text).split(" ")
        if (args.size < 2) {
            return this.telegramCommandJson("approve", "usage", ok: false, message: "usage: /approve <approvalId> <allow-once|deny>").toJsonString()
        }
        let result = gatewayResolveTelegramApprovalCallback("[telegram-approval]\napprovalId=${args[0]}\ndecision=${args[1]}\nby=${senderId}", user)
        gatewayTelegramApprovalResolverReply(result)
    }

    private func renderTelegramRestartCommand(): String {
        this.telegramCommandJson("restart", "approval_required", ok: false, message: "Gateway restart is visible but requires the Gateway control approval surface; it is not executed directly from Telegram.").toJsonString()
    }

    private func renderTelegramBashCommand(text: String): String {
        let command = this.telegramCommandArgText(text)
        let out = this.telegramCommandJson("bash", "approval_required", ok: false, message: "Host shell execution requires Metis exec approval and was not executed.")
        out.put("command", JsonString(command))
        out.toJsonString()
    }

    private func renderTelegramSkillCommand(text: String): String {
        let name = this.telegramCommandArgText(text).split(" ")[0].trimAscii()
        let out = this.telegramCommandJson("skill", if (name.isEmpty()) { "usage" } else { "not_found" }, ok: false)
        out.put("skill", JsonString(name))
        out.put("message", JsonString(if (name.isEmpty()) { "usage: /skill <name> <input>" } else { "No Telegram-native skill runner is bound for '${name}'. Use normal chat or the skills control surface." }))
        out.toJsonString()
    }

    private func renderTelegramBtwCommand(text: String): String {
        let question = this.telegramCommandArgText(text)
        let out = this.telegramCommandJson("btw", if (question.isEmpty()) { "usage" } else { "not_supported" }, ok: false)
        out.put("message", JsonString(if (question.isEmpty()) { "usage: /btw <question>" } else { "One-shot non-persistent turns are not supported by the current Gateway Telegram native runtime." }))
        out.toJsonString()
    }

    private func renderTelegramTtsCommand(text: String): String {
        let action = this.telegramCommandArgText(text).split(" ")[0].trimAscii().toAsciiLower()
        let out = this.telegramCommandJson("tts", "not_configured", ok: false)
        out.put("requested", JsonString(if (action.isEmpty()) { "status" } else { action }))
        out.put("message", JsonString("No Metis TTS provider is configured for Telegram native voice output."))
        out.toJsonString()
    }

    private func renderTelegramSubagentsFallback(text: String): String {
        let out = this.telegramCommandJson("subagents", "usage", ok: false, message: "Invalid subagent command.")
        out.put("input", JsonString(text))
        out.toJsonString()
    }

    private func telegramCommandName(text: String): String {
        gatewayTelegramNativeCommandNameFromText(text)
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
        payload.put("args", JsonString(this.telegramCommandArgText(message.text)))
        payload.put("from", JsonString(message.senderId.trimAscii()))
        payload.put("to", JsonString(message.peerId.trimAscii()))
        payload.put("isAuthorizedSender", true.toJsonValue())
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
        payload.put("from", JsonString(message.senderId.trimAscii()))
        payload.put("to", JsonString(message.peerId.trimAscii()))
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
            case Some(v) =>
                payload.put("threadId", JsonString(v.trimAscii()))
                payload.put("messageThreadId", JsonString(v.trimAscii()))
            case None =>
                payload.put("threadId", JsonString(""))
                payload.put("messageThreadId", JsonString(""))
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
            let status = this.telegramJsonString(result, "status", "error")
            if (status == "unsupported") {
                let unsupported = match (result.get("unsupportedCapability")) {
                    case Some(v) => v.toJsonString()
                    case None => "null"
                }
                this.sendTextToPeerDetailed(
                    "telegram",
                    message.peerId,
                    "{\"ok\":false,\"status\":\"unsupported\",\"action\":\"${fallbackAction}\",\"reason\":\"${this.telegramCallbackJsonEscape(reason)}\",\"unsupportedCapability\":${unsupported}}",
                    replyToMessageId: message.replyTargetMessageId,
                    replyInThread: message.replyInThread,
                    accountId: accountId
                )
                return true
            }
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
        if (kind == "answercallbackquery" || kind == "answer-callback-query" || kind == "answer-callback") {
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

    private func telegramModelProviderFromRef(modelRef: String): String {
        let value = modelRef.trimAscii()
        match (value.indexOf(":")) {
            case Some(idx) => if (idx > 0) { return value[..idx].trimAscii().toAsciiLower() }
            case None => ()
        }
        match (value.indexOf("/")) {
            case Some(idx) => if (idx > 0) { return value[..idx].trimAscii().toAsciiLower() }
            case None => ()
        }
        ""
    }

    private func telegramModelIdFromRef(modelRef: String): String {
        let value = modelRef.trimAscii()
        match (value.indexOf(":")) {
            case Some(idx) => if (idx + 1 < value.size) { return value[idx + 1..].trimAscii() }
            case None => ()
        }
        match (value.indexOf("/")) {
            case Some(idx) => if (idx + 1 < value.size) { return value[idx + 1..].trimAscii() }
            case None => ()
        }
        value
    }

    private func telegramNormalizeModelRef(raw: String): String {
        let value = raw.trimAscii()
        if (value.contains(":")) {
            return value
        }
        match (value.indexOf("/")) {
            case Some(idx) =>
                if (idx > 0 && idx + 1 < value.size) {
                    return "${value[..idx].trimAscii()}:${value[idx + 1..].trimAscii()}"
                }
            case None => ()
        }
        value
    }

    private func telegramAddModelCandidate(out: ArrayList<String>, provider: String, modelRef: String): Unit {
        let modelProvider = this.telegramModelProviderFromRef(modelRef)
        if (modelProvider != provider.trimAscii().toAsciiLower()) {
            return
        }
        let modelId = this.telegramModelIdFromRef(modelRef)
        if (!modelId.isEmpty() && !out.contains(modelId)) {
            out.add(modelId)
        }
    }

    private func telegramModelCandidatesForProvider(provider: String, current: String): Array<String> {
        let normalizedProvider = provider.trimAscii().toAsciiLower()
        let out = ArrayList<String>()
        for (descriptor in cliSetupVisibleModelProviders()) {
            if (descriptor.providerId == normalizedProvider) {
                this.telegramAddModelCandidate(out, normalizedProvider, descriptor.defaultModelRef)
            }
        }
        for (choice in cliFindModelAuthChoicesForProvider(normalizedProvider)) {
            this.telegramAddModelCandidate(out, normalizedProvider, choice.defaultModelRef)
        }
        this.telegramAddModelCandidate(out, normalizedProvider, current)
        out.toArray()
    }

    private func telegramModelCallbackFits(data: String): Bool {
        data.trimAscii().size <= 64
    }

    private func telegramModelsProviderFromCommand(text: String): String {
        let parts = text.trimAscii().split(" ")
        if (parts.size >= 2) {
            let candidate = parts[1].trimAscii()
            try {
                let _ = Int64.parse(candidate)
                return ""
            } catch (_e: Exception) {
                return candidate.toAsciiLower()
            }
        }
        ""
    }

    private func telegramModelsPageFromCommand(text: String): Int64 {
        let parts = text.trimAscii().split(" ")
        if (parts.size >= 3) {
            try { return Int64.parse(parts[2].trimAscii()) } catch (_e: Exception) { return 1 }
        }
        if (parts.size >= 2) {
            try { return Int64.parse(parts[1].trimAscii()) } catch (_e: Exception) { return 1 }
        }
        1
    }

    private func renderTelegramModelsEntry(
        user: GatewayUserSettings,
        sessionKey: String,
        commandText!: String = "/models",
        callbackProvider!: String = "",
        callbackPage!: Int64 = 1
    ): String {
        let current = this.telegramCurrentModelRef(user, sessionKey)
        let currentText = if (current.trimAscii().isEmpty()) { "global default" } else { current.trimAscii() }
        let providers = cliSetupVisibleModelProviders()
        let provider = if (!callbackProvider.trimAscii().isEmpty()) {
            callbackProvider.trimAscii().toAsciiLower()
        } else {
            this.telegramModelsProviderFromCommand(commandText)
        }
        if (!provider.isEmpty()) {
            return this.renderTelegramProviderModels(user, sessionKey, provider, if (callbackProvider.trimAscii().isEmpty()) { this.telegramModelsPageFromCommand(commandText) } else { callbackPage })
        }
        if (!user.telegram.actions.inlineKeyboard || !user.telegram.actions.callbackQuery) {
            let lines = ArrayList<String>()
            lines.add("Telegram models")
            lines.add("Current: ${currentText}")
            for (descriptor in providers) {
                let models = this.telegramModelCandidatesForProvider(descriptor.providerId, current)
                let currentMark = if (this.telegramModelProviderFromRef(current) == descriptor.providerId) { " current" } else { "" }
                lines.add("- ${descriptor.providerId} (${models.size}) default=${descriptor.defaultModelRef}${currentMark}")
            }
            lines.add("Use: /models <provider>")
            lines.add("Switch: /model <provider/model>")
            return String.join(lines.toArray(), delimiter: "\n")
        }
        let lines = ArrayList<String>()
        lines.add("[inline-keyboard]")
        lines.add("text=Telegram models\nCurrent: ${currentText}\nSelect a provider.")
        for (idx in 0..providers.size) {
            let descriptor = providers[idx]
            let models = this.telegramModelCandidatesForProvider(descriptor.providerId, current)
            let currentMark = if (this.telegramModelProviderFromRef(current) == descriptor.providerId) { " · current" } else { "" }
            let data = "models:list:${descriptor.providerId}:1"
            if (this.telegramModelCallbackFits(data)) {
                lines.add("button=${descriptor.providerId} (${models.size})${currentMark}|callback:${data}")
            }
        }
        String.join(lines.toArray(), delimiter: "\n")
    }

    private func renderTelegramProviderModels(user: GatewayUserSettings, sessionKey: String, provider: String, page: Int64): String {
        let normalizedProvider = provider.trimAscii().toAsciiLower()
        let current = this.telegramCurrentModelRef(user, sessionKey)
        let currentText = if (current.trimAscii().isEmpty()) { "global default" } else { current.trimAscii() }
        let models = this.telegramModelCandidatesForProvider(normalizedProvider, current)
        if (models.isEmpty()) {
            return "Unknown provider or no models: ${normalizedProvider}\nUse: /models"
        }
        let pageSize: Int64 = 8
        let total = Int64(models.size)
        let totalPages = if (total <= 0) { 1 } else { (total + pageSize - 1) / pageSize }
        var effectivePage = page
        if (effectivePage < 1) { effectivePage = 1 }
        if (effectivePage > totalPages) { effectivePage = totalPages }
        if (!user.telegram.actions.inlineKeyboard || !user.telegram.actions.callbackQuery) {
            let lines = ArrayList<String>()
            lines.add("Models (${normalizedProvider}) - ${total} available")
            lines.add("Current: ${currentText}")
            lines.add("Page: ${effectivePage}/${totalPages}")
            let start = (effectivePage - 1) * pageSize
            let end = if (start + pageSize > total) { total } else { start + pageSize }
            for (idx in start..end) {
                let model = models[idx]
                let ref = "${normalizedProvider}:${model}"
                let mark = if (ref == current.trimAscii()) { " *current*" } else { "" }
                lines.add("- ${normalizedProvider}/${model}${mark}")
            }
            lines.add("Back: /models")
            lines.add("Switch: /model <provider/model>")
            return String.join(lines.toArray(), delimiter: "\n")
        }
        let lines = ArrayList<String>()
        lines.add("[inline-keyboard]")
        lines.add("text=Models (${normalizedProvider}) - ${total} available\nCurrent: ${currentText}\nPage: ${effectivePage}/${totalPages}")
        let start = (effectivePage - 1) * pageSize
        let end = if (start + pageSize > total) { total } else { start + pageSize }
        for (idx in start..end) {
            let model = models[idx]
            let ref = "${normalizedProvider}:${model}"
            let mark = if (ref == current.trimAscii()) { " ✓" } else { "" }
            let data = "models:setidx:${normalizedProvider}:${effectivePage}:${idx - start}"
            if (this.telegramModelCallbackFits(data)) {
                lines.add("button=${model}${mark}|callback:${data}")
            }
        }
        if (totalPages > 1) {
            if (effectivePage > 1) {
                let prevData = "models:list:${normalizedProvider}:${effectivePage - 1}"
                if (this.telegramModelCallbackFits(prevData)) { lines.add("button=Prev|callback:${prevData}") }
            }
            if (effectivePage < totalPages) {
                let nextData = "models:list:${normalizedProvider}:${effectivePage + 1}"
                if (this.telegramModelCallbackFits(nextData)) { lines.add("button=Next|callback:${nextData}") }
            }
        }
        lines.add("button=Back|callback:models:providers")
        String.join(lines.toArray(), delimiter: "\n")
    }

    private func resolveTelegramModelCallback(data: String, senderId: String, user: GatewayUserSettings, sessionKey: String): String {
        var modelRef = ""
        if (data.startsWith("models:setidx:")) {
            let parts = data.split(":")
            if (parts.size >= 5) {
                let provider = parts[2].trimAscii().toAsciiLower()
                let page = try { Int64.parse(parts[3].trimAscii()) } catch (_e: Exception) { 1 }
                let offset = try { Int64.parse(parts[4].trimAscii()) } catch (_e: Exception) { -1 }
                let models = this.telegramModelCandidatesForProvider(provider, this.telegramCurrentModelRef(user, sessionKey))
                let idx = (if (page < 1) { 1 } else { page } - 1) * 8 + offset
                if (idx >= 0 && idx < Int64(models.size)) {
                    modelRef = "${provider}:${models[idx]}"
                }
            }
        } else if (data.startsWith("models:set:")) {
            modelRef = data["models:set:".size..].trimAscii()
        }
        return this.applyTelegramModelSelection(modelRef, senderId, user, sessionKey)
    }

    private func applyTelegramModelSelection(rawModelRef: String, senderId: String, user: GatewayUserSettings, sessionKey: String): String {
        if (!this.telegramSenderCanOperate(senderId, user)) {
            return "Model switch denied: sender ${senderId} is not authorized."
        }
        if (!user.telegram.configWrites) {
            return "Model switch denied: gateway.telegram.configWrites is disabled."
        }
        let modelRef = this.telegramNormalizeModelRef(rawModelRef)
        if (modelRef.isEmpty() || modelRef.size > 128 || !modelRef.contains(":")) {
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
