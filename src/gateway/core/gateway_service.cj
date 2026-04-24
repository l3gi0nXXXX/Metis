package metis.gateway.core

import metis.core.config.CliSettingManager
import metis.gateway.model.*
import metis.gateway.session.{GatewaySessionContext, gatewaySessionRequestFromInbound}
import magic.log.LogUtils
import std.time.DateTime
import stdx.encoding.json.JsonObject

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
        LogUtils.info("Gateway.service.timing: step=startChannels elapsedMs=${this.startNowMs() - startMs}")
    }

    /**
     * 停止所有渠道。
     */
    public func stop(): Unit {
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

        let conversationKey = decision.conversationKey.getOrThrow()
        let request = gatewaySessionRequestFromInbound(message, sessionHint: conversationKey, accountId: effectiveAccountId)
        let user = CliSettingManager.readGatewaySettings()
        let turn = gatewayExecuteSessionRequestTurnForUser(
            user,
            request,
            message.text,
            deliver: true,
            replyToMessageId: message.replyTargetMessageId ?? Some(message.messageId),
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
            return
        }
        LogUtils.error("Gateway.send: deliveryStatus=${execution.deliveryStatus} err=${execution.deliveryError}")
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
        let nm = adapterName.trimAscii()
        let user = CliSettingManager.readGatewaySettings()
        let (effectiveReplyToMessageId, effectiveReplyInThread, degraded, policyReason) =
            gatewayApplyOutboundChannelPolicy(user, nm, replyToMessageId, replyInThread)
        if (degraded) {
            LogUtils.info("Gateway.sendTextToPeer policy: channel=${nm} peer=${peerId} degraded=true reason=${policyReason}")
        }
        let outbound = OutboundMessage(
            channelTypeFromAdapterName(nm),
            peerId,
            text,
            replyToMessageId: effectiveReplyToMessageId,
            replyInThread: effectiveReplyInThread,
            accountId: accountId
        )
        match (this.channelManager.getAdapter(nm)) {
            case Some(adapter) =>
                let sentMessageId = adapter.sendWithMessageId(outbound)
                if (!sentMessageId.trimAscii().isEmpty()) {
                    LogUtils.info("Gateway.sendTextToPeer: channel=${nm} peer=${peerId} ok")
                    return sentMessageId
                }
            case None => ()
        }
        let send = this.channelManager.sendToAdapterName(nm, outbound)
        if (send.delivered) {
            LogUtils.info("Gateway.sendTextToPeer: channel=${nm} peer=${peerId} ok")
            return send.messageId
        }
        LogUtils.error("Gateway.sendTextToPeer: no adapter for channel='${nm}' peer=${peerId} lastReason=${send.lastReason}")
        throw Exception("no adapter for channel='${nm}' peer=${peerId} lastReason=${send.lastReason}")
    }
}
