package metis.gateway.runtime

import metis.gateway.model.GatewayConfig

import stdx.net.http.HttpContext

// Thin compatibility shim retained while remaining callers migrate off the
// historical dashboard filename. Control-ui content now lives in
// gateway_control_ui_content.cj and server lifecycle lives in
// gateway_control_ui_server.cj.
public func gatewayControlUiHandleAuthedJson(ctx: HttpContext, requiredMethod: String, deliver: () -> String): String {
    gatewayControlUiContentHandleAuthedJson(ctx, requiredMethod, deliver)
}

// Thin compatibility shim retained while remaining callers migrate off the
// historical dashboard filename.
public func gatewayBuildControlUiHtml(cfg: GatewayConfig): String {
    gatewayBuildControlUiContentHtml(cfg)
}
