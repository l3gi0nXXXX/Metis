package metis.gateway.core

import metis.gateway.session.{GatewaySessionContext, GatewaySessionRequest, gatewayResolveDeliveryTarget, gatewayResolveSessionContext}

public func gatewayResolveSessionContextWithAgentRoute(request: GatewaySessionRequest): GatewaySessionContext {
    let base = gatewayResolveSessionContext(request)
    if (request.routeRoot.size() == 0 || request.routePeerKind.isEmpty() || request.routePeerId.isEmpty()) {
        return base
    }

    let route = gatewayResolveAgentRoute(
        GatewayAgentRouteInput(
            request.routeRoot,
            base.channelName,
            accountId: request.routeAccountId,
            defaultAccountId: request.routeDefaultAccountId,
            peerKind: request.routePeerKind,
            peerId: request.routePeerId,
            parentPeerKind: request.routeParentPeerKind,
            parentPeerId: request.routeParentPeerId,
            senderId: request.senderId,
            dmScope: request.dmScope
        )
    )
    let deliveryTarget = gatewayResolveDeliveryTarget(request, route.sessionKey, preferredAccountId: route.preferredAccountId)
    GatewaySessionContext(
        request.source,
        base.sourceLabel,
        base.channelName,
        route.sessionKey,
        route.agentId,
        accountId: route.accountId,
        preferredAccountId: route.preferredAccountId,
        matchedBy: route.matchedBy,
        lastRoutePolicy: route.lastRoutePolicy,
        routeDiagnostics: route.diagnostics,
        lane: request.lane,
        deliveryTarget: deliveryTarget
    )
}
