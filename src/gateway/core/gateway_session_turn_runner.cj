package metis.gateway.core

import metis.core.GatewayToolRuntimeContext
import metis.core.config.GatewayUserSettings
import metis.gateway.session.{GatewaySessionContext, GatewaySessionRequest, gatewayResolveSessionContext}

public class GatewayResolvedSessionTurnResult {
    public let context: GatewaySessionContext
    public let execution: GatewaySessionExecutionResult

    public init(context: GatewaySessionContext, execution: GatewaySessionExecutionResult) {
        this.context = context
        this.execution = execution
    }
}

public func gatewayStreamingEnabledForUserChannel(user: GatewayUserSettings, channelName: String): Bool {
    let normalized = channelName.trimAscii().toAsciiLower()
    if (normalized == "telegram" || normalized == "feishu" || normalized == "qq") {
        let (mode, blocked) = if (normalized == "telegram") {
            (user.telegram.streaming.trimAscii().toAsciiLower(), user.telegram.blockStreaming)
        } else if (normalized == "feishu") {
            (user.feishu.streaming.trimAscii().toAsciiLower(), user.feishu.blockStreaming)
        } else {
            (user.qq.streaming.trimAscii().toAsciiLower(), user.qq.blockStreaming)
        }
        if (blocked) {
            return false
        }
        return !(mode.isEmpty() || mode == "off" || mode == "false" || mode == "disabled" || mode == "none")
    }
    return normalized == "control-ui" || normalized == "dashboard" || normalized == "cli"
}

public func gatewayBridgeForSessionRequest(user: GatewayUserSettings, request: GatewaySessionRequest): AgentBridge {
    let store = gatewaySessionStoreForResolvedRequest(user, request)
    AgentBridge(sessionStore: store)
}

public func gatewayExecuteSessionRequestTurn(
    bridge: AgentBridge,
    request: GatewaySessionRequest,
    prompt: String,
    deliver!: Bool = false,
    extraSystemPrompt!: String = "",
    timeoutSeconds!: Int64 = 0,
    bestEffortDeliver!: Bool = false,
    replyToMessageId!: Option<String> = None,
    replyInThread!: Bool = false,
    deliverHook!: Option<(String, String, String, String, Option<String>, Bool) -> String> = None<(String, String, String, String, Option<String>, Bool) -> String>,
    transcriptHook!: Option<(GatewaySessionContext, Int64, String, String) -> Unit> = None<(GatewaySessionContext, Int64, String, String) -> Unit>,
    streamHook!: Option<(GatewaySessionContext, String) -> Unit> = None<(GatewaySessionContext, String) -> Unit>,
    streamingEnabled!: Bool = false
): GatewayResolvedSessionTurnResult {
    let context = gatewayResolveSessionContext(request)
    let toolRuntimeContext = GatewayToolRuntimeContext(
        context.sourceLabel,
        channelName: context.channelName,
        sessionKey: context.sessionKey,
        senderId: request.senderId,
        declaredUser: request.declaredUser,
        operatorScopes: request.operatorScopes,
        prompt: prompt
    )
    match (context.deliveryTarget) {
        case Some(target) =>
            // Persist the latest real delivery/binding target so later catalog views do not need to infer
            // conversation/thread/reply metadata from the session key alone.
            bridge.getSessionStore().appendBindingSnapshot(context.sessionKey, target)
        case None => ()
    }
    let execution = gatewayExecuteSessionTurn(
        bridge,
        context,
        prompt,
        deliver: deliver,
        extraSystemPrompt: extraSystemPrompt,
        timeoutSeconds: timeoutSeconds,
        toolRuntimeContext: Some(toolRuntimeContext),
        bestEffortDeliver: bestEffortDeliver,
        replyToMessageId: replyToMessageId,
        replyInThread: replyInThread,
        deliverHook: deliverHook,
        transcriptHook: transcriptHook,
        streamHook: streamHook,
        streamingEnabled: streamingEnabled
    )
    GatewayResolvedSessionTurnResult(context, execution)
}

public func gatewayExecuteSessionRequestTurnForUser(
    user: GatewayUserSettings,
    request: GatewaySessionRequest,
    prompt: String,
    deliver!: Bool = false,
    extraSystemPrompt!: String = "",
    timeoutSeconds!: Int64 = 0,
    bestEffortDeliver!: Bool = false,
    replyToMessageId!: Option<String> = None,
    replyInThread!: Bool = false,
    deliverHook!: Option<(String, String, String, String, Option<String>, Bool) -> String> = None<(String, String, String, String, Option<String>, Bool) -> String>,
    transcriptHook!: Option<(GatewaySessionContext, Int64, String, String) -> Unit> = None<(GatewaySessionContext, Int64, String, String) -> Unit>,
    streamHook!: Option<(GatewaySessionContext, String) -> Unit> = None<(GatewaySessionContext, String) -> Unit>
): GatewayResolvedSessionTurnResult {
    let bridge = gatewayBridgeForSessionRequest(user, request)
    let context = gatewayResolveSessionContext(request)
    gatewayExecuteSessionRequestTurn(
        bridge,
        request,
        prompt,
        deliver: deliver,
        extraSystemPrompt: extraSystemPrompt,
        timeoutSeconds: timeoutSeconds,
        bestEffortDeliver: bestEffortDeliver,
        replyToMessageId: replyToMessageId,
        replyInThread: replyInThread,
        deliverHook: deliverHook,
        transcriptHook: transcriptHook,
        streamHook: streamHook,
        streamingEnabled: gatewayStreamingEnabledForUserChannel(user, context.channelName)
    )
}
