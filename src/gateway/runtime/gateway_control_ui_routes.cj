package metis.gateway.runtime

import metis.gateway.model.GatewayConfig

import stdx.net.http.*

private func gatewayControlUiReplyHtml(ctx: HttpContext, body: String, csp: String): Unit {
    let rb = ctx.responseBuilder
    rb.header("content-type", "text/html; charset=utf-8")
    rb.header("content-security-policy", csp)
    rb.body(body)
}

private func gatewayControlUiReplyJson(ctx: HttpContext, requiredMethod: String, deliver: () -> String): Unit {
    let rb = ctx.responseBuilder
    rb.header("content-type", "application/json; charset=utf-8")
    rb.body(gatewayControlUiContentHandleAuthedJson(ctx, requiredMethod, deliver))
}

private func gatewayControlUiReplyOpenJson(ctx: HttpContext, deliver: () -> String): Unit {
    let rb = ctx.responseBuilder
    rb.header("content-type", "application/json; charset=utf-8")
    rb.header("cache-control", "no-cache")
    rb.body(deliver())
}

private func gatewayControlUiReplyResolvedIndexHtml(ctx: HttpContext, cfg: GatewayConfig, csp: String): Unit {
    let state = gatewayControlUiResolveRootState(cfg)
    if (state.kind == "resolved" || state.kind == "bundled") {
        if (let Some(html) <- gatewayControlUiRootIndexHtml(cfg)) {
            gatewayControlUiReplyHtml(ctx, html, csp)
            return
        }
    }
    if (state.kind == "inline-fallback") {
        gatewayControlUiReplyHtml(ctx, gatewayBuildControlUiContentHtml(cfg), csp)
        return
    }
    gatewayControlUiReplyHtml(ctx, gatewayControlUiAssetsUnavailableHtml(cfg, state), csp)
}

public func gatewayRegisterControlUiRoutes(server: Server, cfg: GatewayConfig): Unit {
    let contract = GatewayControlUiRuntime.controlUiContract(cfg)
    gatewayRegisterControlUiStaticAssetRoutes(server, cfg)
    GatewayControlUiRuntime.registerRoute(server, cfg, "/ws", { ctx =>
        gatewayHandleControlUiWebSocket(ctx, cfg)
    })
    for (routePath in gatewayControlUiSpaRoutes("")) {
        GatewayControlUiRuntime.registerRoute(server, cfg, routePath, { ctx =>
            gatewayControlUiReplyResolvedIndexHtml(ctx, cfg, contract.csp)
        })
    }
    GatewayControlUiRuntime.registerRoute(server, cfg, CONTROL_UI_BOOTSTRAP_CONFIG_PATH, { ctx =>
        gatewayControlUiReplyOpenJson(ctx, { => gatewayControlUiBootstrapConfigJson(cfg).toJsonString() })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, CONTROL_UI_AUTH_CONFIG_PATH, { ctx =>
        gatewayControlUiReplyOpenJson(ctx, { => gatewayControlUiBrowserAuthConfigJson(cfg).toJsonString() })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/status", { ctx =>
        gatewayControlUiReplyJson(ctx, "status", { => gatewayDashboardBuildStatusJson(ctx) })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/chat/history", { ctx =>
        gatewayControlUiReplyJson(ctx, "sessions.list", { => gatewayDashboardBuildChatHistoryJson(ctx) })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/sessions/list", { ctx =>
        gatewayControlUiReplyJson(ctx, "sessions.list", { => gatewayDashboardBuildSessionsJson() })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/subagents/list", { ctx =>
        gatewayControlUiReplyJson(ctx, "subagents.list", { => gatewayDashboardBuildSubagentsJson() })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/subagents/status", { ctx =>
        gatewayControlUiReplyJson(ctx, "subagents.status", { => gatewayDashboardBuildSubagentStatusJson(ctx) })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/subagents/logs", { ctx =>
        gatewayControlUiReplyJson(ctx, "subagents.logs", { => gatewayDashboardBuildSubagentLogsJson(ctx) })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/subagents/kill", { ctx =>
        gatewayControlUiReplyJson(ctx, "subagents.kill", { => gatewayDashboardHandleSubagentKill(ctx) })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/chat/send", { ctx =>
        gatewayControlUiReplyJson(ctx, "http.responses", { => gatewayDashboardHandleChatSend(ctx) })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/models", { ctx =>
        gatewayControlUiReplyJson(ctx, "models.status", { => gatewayDashboardBuildModelsJson() })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/model", { ctx =>
        gatewayControlUiReplyJson(ctx, "config.apply", { => gatewayDashboardHandleModelSwitch(ctx) })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/skills", { ctx =>
        gatewayControlUiReplyJson(ctx, "status", { => gatewayDashboardBuildSkillsJson() })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/skills/compatibility", { ctx =>
        gatewayControlUiReplyJson(ctx, "status", { => gatewayDashboardBuildSkillsCompatibilityJson() })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/skills/set", { ctx =>
        gatewayControlUiReplyJson(ctx, "config.apply", { => gatewayDashboardHandleSkillSet(ctx) })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/sessions/delete", { ctx =>
        gatewayControlUiReplyJson(ctx, "config.apply", { => gatewayDashboardHandleSessionsDelete(ctx) })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/cron", { ctx =>
        gatewayControlUiReplyJson(ctx, "config.apply", { => gatewayDashboardHandleCronPost(ctx) })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/doctor", { ctx =>
        gatewayControlUiReplyJson(ctx, "status", { => gatewayDashboardBuildDoctorJson() })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/channels/status", { ctx =>
        gatewayControlUiReplyJson(ctx, "channels.status", { => gatewayDashboardBuildChannelsJson(ctx) })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/channels/runtime", { ctx =>
        gatewayControlUiReplyJson(ctx, "channels.runtime", { => gatewayDashboardBuildChannelsRuntimeJson(ctx) })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/channels/health", { ctx =>
        gatewayControlUiReplyJson(ctx, "channels.health", { => gatewayDashboardBuildChannelsHealthJson(ctx) })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/channels/audit", { ctx =>
        gatewayControlUiReplyJson(ctx, "channels.audit", { => gatewayDashboardBuildChannelsAuditJson(ctx: Some(ctx)) })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/agents/status", { ctx =>
        gatewayControlUiReplyJson(ctx, "agents.status", { => gatewayDashboardBuildAgentsJson() })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/agents/runtime", { ctx =>
        gatewayControlUiReplyJson(ctx, "agents.runtime.profile", { => gatewayDashboardBuildAgentsRuntimeJson() })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/agents/runtime/audit", { ctx =>
        gatewayControlUiReplyJson(ctx, "agents.runtime.audit", { => gatewayDashboardBuildAgentsRuntimeAuditJson() })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/memory/status", { ctx =>
        gatewayControlUiReplyJson(ctx, "status", { => gatewayDashboardBuildMemoryStatusJson(ctx: Some(ctx)) })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/control-ui-assets", { ctx =>
        gatewayControlUiReplyJson(ctx, "status", { => gatewayDashboardBuildControlUiAssetsJson() })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/config/get", { ctx =>
        gatewayControlUiReplyJson(ctx, "status", { => gatewayDashboardBuildConfigGetJson(ctx) })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/config/schema", { ctx =>
        gatewayControlUiReplyJson(ctx, "status", { => gatewayDashboardBuildConfigSchemaJson(ctx) })
    })
    GatewayControlUiRuntime.registerRoute(server, cfg, "/api/config/patch", { ctx =>
        gatewayControlUiReplyJson(ctx, "config.apply", { => gatewayDashboardHandleConfigPatch(ctx) })
    })
}
