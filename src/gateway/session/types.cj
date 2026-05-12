package metis.gateway.session

import metis.gateway.model.ChatType
import stdx.encoding.json.JsonObject

public enum GatewayIngressSource {
    | Cli
    | ControlUi
    | DashboardRpc
    | GatewayRpc
    | Channel(String)
    | Cron
    | Unknown(String)
}

public class GatewayDeliveryTarget {
    public let channelName: String
    public let peerId: String
    public let accountId: String
    public let conversationId: String
    public let threadId: String
    public let sourceMessageId: String
    public let replyToMessageId: String
    public let replyInThread: Bool

    public init(
        channelName: String,
        peerId: String,
        accountId!: String = "",
        conversationId!: String = "",
        threadId!: String = "",
        sourceMessageId!: String = "",
        replyToMessageId!: String = "",
        replyInThread!: Bool = false
    ) {
        this.channelName = channelName.trimAscii().toAsciiLower()
        this.peerId = peerId.trimAscii()
        this.accountId = accountId.trimAscii()
        this.conversationId = conversationId.trimAscii()
        this.threadId = threadId.trimAscii()
        this.sourceMessageId = sourceMessageId.trimAscii()
        this.replyToMessageId = replyToMessageId.trimAscii()
        this.replyInThread = replyInThread
    }
}

public class GatewaySessionRequest {
    public let source: GatewayIngressSource
    public let channelName: String
    public let sessionHint: String
    public let agentId: String
    public let text: String
    public let accountId: String
    public let peerId: String
    public let senderId: String
    public let declaredUser: String
    public let operatorScopes: Array<String>
    public let conversationId: String
    public let threadId: String
    public let sourceMessageId: String
    public let chatType: Option<ChatType>
    public let dmScope: String
    public let to: String
    public let lane: String
    public let replyChannel: String
    public let replyTo: String
    public let replyAccountId: String
    public let replyToMessageId: String
    public let replyInThread: Bool
    public let deliver: Bool
    public let mediaContext: JsonObject
    public let routeRoot: JsonObject
    public let routeAccountId: String
    public let routeDefaultAccountId: String
    public let routePeerKind: String
    public let routePeerId: String
    public let routeParentPeerKind: String
    public let routeParentPeerId: String

    public init(
        source: GatewayIngressSource,
        channelName!: String = "",
        sessionHint!: String = "",
        agentId!: String = "",
        text!: String = "",
        accountId!: String = "",
        peerId!: String = "",
        senderId!: String = "",
        declaredUser!: String = "",
        operatorScopes!: Array<String> = [],
        conversationId!: String = "",
        threadId!: String = "",
        sourceMessageId!: String = "",
        chatType!: Option<ChatType> = None,
        dmScope!: String = "per-chat",
        to!: String = "",
        lane!: String = "",
        replyChannel!: String = "",
        replyTo!: String = "",
        replyAccountId!: String = "",
        replyToMessageId!: String = "",
        replyInThread!: Bool = false,
        deliver!: Bool = false,
        mediaContext!: JsonObject = JsonObject(),
        routeRoot!: JsonObject = JsonObject(),
        routeAccountId!: String = "",
        routeDefaultAccountId!: String = "",
        routePeerKind!: String = "",
        routePeerId!: String = "",
        routeParentPeerKind!: String = "",
        routeParentPeerId!: String = ""
    ) {
        this.source = source
        this.channelName = channelName.trimAscii().toAsciiLower()
        this.sessionHint = sessionHint.trimAscii()
        this.agentId = agentId.trimAscii()
        this.text = text
        this.accountId = accountId.trimAscii()
        this.peerId = peerId.trimAscii()
        this.senderId = senderId.trimAscii()
        this.declaredUser = declaredUser.trimAscii()
        this.operatorScopes = operatorScopes
        this.conversationId = conversationId.trimAscii()
        this.threadId = threadId.trimAscii()
        this.sourceMessageId = sourceMessageId.trimAscii()
        this.chatType = chatType
        this.dmScope = dmScope.trimAscii().toAsciiLower()
        this.to = to.trimAscii()
        this.lane = lane.trimAscii()
        this.replyChannel = replyChannel.trimAscii().toAsciiLower()
        this.replyTo = replyTo.trimAscii()
        this.replyAccountId = replyAccountId.trimAscii()
        this.replyToMessageId = replyToMessageId.trimAscii()
        this.replyInThread = replyInThread
        this.deliver = deliver
        this.mediaContext = mediaContext
        this.routeRoot = routeRoot
        this.routeAccountId = routeAccountId.trimAscii()
        this.routeDefaultAccountId = routeDefaultAccountId.trimAscii()
        this.routePeerKind = routePeerKind.trimAscii().toAsciiLower()
        this.routePeerId = routePeerId.trimAscii()
        this.routeParentPeerKind = routeParentPeerKind.trimAscii().toAsciiLower()
        this.routeParentPeerId = routeParentPeerId.trimAscii()
    }
}

public class GatewayTurnContext {
    public let agentId: String
    public let workspaceDir: String
    public let agentDir: String
    public let modelsJsonPath: String
    public let authProfilesPath: String
    public let legacyAuthPath: String
    public let sessionsDir: String
    public let sessionKey: String
    public let mainSessionKey: String
    public let matchedBy: String
    public let lastRoutePolicy: String
    public let modelRef: String
    public let channelName: String
    public let accountId: String
    public let peerId: String
    public let threadId: String
    public let route: JsonObject
    public let agentScope: JsonObject

    public init(
        agentId: String,
        workspaceDir!: String = "",
        agentDir!: String = "",
        modelsJsonPath!: String = "",
        authProfilesPath!: String = "",
        legacyAuthPath!: String = "",
        sessionsDir!: String = "",
        sessionKey!: String = "",
        mainSessionKey!: String = "",
        matchedBy!: String = "",
        lastRoutePolicy!: String = "",
        modelRef!: String = "",
        channelName!: String = "",
        accountId!: String = "",
        peerId!: String = "",
        threadId!: String = "",
        route!: JsonObject = JsonObject(),
        agentScope!: JsonObject = JsonObject()
    ) {
        this.agentId = agentId.trimAscii()
        this.workspaceDir = workspaceDir.trimAscii()
        this.agentDir = agentDir.trimAscii()
        this.modelsJsonPath = modelsJsonPath.trimAscii()
        this.authProfilesPath = authProfilesPath.trimAscii()
        this.legacyAuthPath = legacyAuthPath.trimAscii()
        this.sessionsDir = sessionsDir.trimAscii()
        this.sessionKey = sessionKey.trimAscii()
        this.mainSessionKey = mainSessionKey.trimAscii()
        this.matchedBy = matchedBy.trimAscii()
        this.lastRoutePolicy = lastRoutePolicy.trimAscii()
        this.modelRef = modelRef.trimAscii()
        this.channelName = channelName.trimAscii().toAsciiLower()
        this.accountId = accountId.trimAscii()
        this.peerId = peerId.trimAscii()
        this.threadId = threadId.trimAscii()
        this.route = route
        this.agentScope = agentScope
    }
}

public class GatewaySessionContext {
    public let sourceLabel: String
    public let channelName: String
    public let sessionKey: String
    public let agentId: String
    public let accountId: String
    public let preferredAccountId: String
    public let matchedBy: String
    public let lastRoutePolicy: String
    public let routeDiagnostics: Array<String>
    public let lane: String
    public let deliveryTarget: Option<GatewayDeliveryTarget>
    public let source: GatewayIngressSource
    public let turnContext: GatewayTurnContext

    public init(
        source: GatewayIngressSource,
        sourceLabel: String,
        channelName: String,
        sessionKey: String,
        agentId: String,
        accountId!: String = "",
        preferredAccountId!: String = "",
        matchedBy!: String = "",
        lastRoutePolicy!: String = "",
        routeDiagnostics!: Array<String> = [],
        lane!: String = "",
        deliveryTarget!: Option<GatewayDeliveryTarget> = None,
        turnContext!: Option<GatewayTurnContext> = None<GatewayTurnContext>
    ) {
        this.source = source
        this.sourceLabel = sourceLabel.trimAscii()
        this.channelName = channelName.trimAscii().toAsciiLower()
        this.sessionKey = sessionKey.trimAscii()
        this.agentId = agentId.trimAscii()
        this.accountId = accountId.trimAscii()
        this.preferredAccountId = preferredAccountId.trimAscii()
        this.matchedBy = matchedBy.trimAscii()
        this.lastRoutePolicy = lastRoutePolicy.trimAscii()
        this.routeDiagnostics = routeDiagnostics
        this.lane = lane.trimAscii()
        this.deliveryTarget = deliveryTarget
        this.turnContext = match (turnContext) {
            case Some(value) => value
            case None => GatewayTurnContext(
                this.agentId,
                sessionKey: this.sessionKey,
                mainSessionKey: "agent:${this.agentId}:main",
                channelName: this.channelName,
                accountId: this.accountId
            )
        }
    }
}

public func gatewayIngressSourceLabel(source: GatewayIngressSource): String {
    match (source) {
        case GatewayIngressSource.Cli => "cli"
        case GatewayIngressSource.ControlUi => "control-ui"
        case GatewayIngressSource.DashboardRpc => "dashboard"
        case GatewayIngressSource.GatewayRpc => "gateway-rpc"
        case GatewayIngressSource.Channel(channel) => channel.trimAscii().toAsciiLower()
        case GatewayIngressSource.Cron => "cron"
        case GatewayIngressSource.Unknown(label) => label.trimAscii().toAsciiLower()
    }
}
