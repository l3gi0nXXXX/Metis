package metis.gateway.core

import metis.core.config.{MetisAgentScope, MetisPaths}
import metis.gateway.session.{GatewaySessionContext, GatewaySessionRequest, GatewayTurnContext, gatewayResolveDeliveryTarget, gatewayResolveSessionContext, gatewayRuntimeRouteContextFromMediaContext}
import stdx.encoding.json.{JsonObject, JsonString}

private func gatewayImRouteScopeString(scope: JsonObject, key: String): String {
    match (scope.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func gatewayImRouteMergePolicyFields(target: JsonObject, raw: JsonObject): Unit {
    for (key in ["systemPrompt", "skills", "tools", "groupPolicy", "policy", "runtimePolicy", "disableAudioPreflight"]) {
        if (target.get(key).isNone()) {
            match (raw.get(key)) {
                case Some(value) => target.put(key, value)
                case None => ()
            }
        }
    }
}

private func gatewayImRouteTurnRoute(route: GatewayAgentRoute, rawRoute!: JsonObject = JsonObject()): JsonObject {
    let out = JsonObject()
    out.put("agentId", JsonString(route.agentId))
    out.put("channel", JsonString(route.channel))
    out.put("accountId", JsonString(route.accountId))
    out.put("preferredAccountId", JsonString(route.preferredAccountId))
    out.put("peerKind", JsonString(route.peerKind))
    out.put("peerId", JsonString(route.peerId))
    out.put("sessionKey", JsonString(route.sessionKey))
    out.put("mainSessionKey", JsonString(route.mainSessionKey))
    out.put("matchedBy", JsonString(route.matchedBy))
    if (!route.lastRoutePolicy.trimAscii().isEmpty()) {
        out.put("lastRoutePolicy", JsonString(route.lastRoutePolicy))
    }
    gatewayImRouteMergePolicyFields(out, rawRoute)
    return out
}

public func gatewayResolveSessionContextWithAgentRoute(request: GatewaySessionRequest): GatewaySessionContext {
    let base = gatewayResolveSessionContext(request)
    if (request.routeRoot.size() == 0 || request.routePeerKind.isEmpty() || request.routePeerId.isEmpty()) {
        return base
    }

    let aliasRoute = gatewayResolveAgentAliasRoute(request.routeRoot, [request.text])
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
            dmScope: request.dmScope,
            explicitAgentId: aliasRoute.agentId,
            explicitMatchedBy: aliasRoute.matchedBy,
            diagnostics: aliasRoute.diagnostics
        )
    )
    let deliveryTarget = gatewayResolveDeliveryTarget(request, route.sessionKey, preferredAccountId: route.preferredAccountId)
    let scope = MetisAgentScope.resolve(
        request.routeRoot,
        agentId: route.agentId,
        homeRoot: MetisPaths.homeRootReadOnly(),
        defaultWorkspace: MetisPaths.workspaceRootReadOnly()
    )
    let turnContext = GatewayTurnContext(
        route.agentId,
        workspaceDir: gatewayImRouteScopeString(scope, "workspaceDir"),
        agentDir: gatewayImRouteScopeString(scope, "agentDir"),
        modelsJsonPath: gatewayImRouteScopeString(scope, "modelsJsonPath"),
        authProfilesPath: gatewayImRouteScopeString(scope, "authProfilesPath"),
        legacyAuthPath: gatewayImRouteScopeString(scope, "legacyAuthPath"),
        sessionsDir: gatewayImRouteScopeString(scope, "sessionsDir"),
        sessionKey: route.sessionKey,
        mainSessionKey: route.mainSessionKey,
        matchedBy: route.matchedBy,
        lastRoutePolicy: route.lastRoutePolicy,
        modelRef: gatewayImRouteScopeString(scope, "modelRef"),
        channelName: base.channelName,
        accountId: route.accountId,
        peerId: request.peerId,
        threadId: request.threadId,
        route: gatewayImRouteTurnRoute(route, rawRoute: gatewayRuntimeRouteContextFromMediaContext(request.mediaContext)),
        agentScope: scope
    )
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
        deliveryTarget: deliveryTarget,
        turnContext: Some(turnContext)
    )
}
