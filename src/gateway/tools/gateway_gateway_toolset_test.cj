package metis.gateway.tools

import metis.core.{GatewayToolRuntimeContext, gatewayActionIsReadOnly, gatewayConfigPathIsProtected, gatewayWithToolRuntimeContext}

import std.unittest.testmacro.*
import stdx.encoding.json.JsonObject

private func gatewayToolsetTestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

@Test
public class GatewayGatewayToolsetTest {
    @TestCase
    public func gatewayToolRecognizesReadOnlyActions(): Unit {
        @Expect(gatewayActionIsReadOnly("status"), true)
        @Expect(gatewayActionIsReadOnly("health"), true)
        @Expect(gatewayActionIsReadOnly("discover"), true)
        @Expect(gatewayActionIsReadOnly("discover.detail"), true)
        @Expect(gatewayActionIsReadOnly("config.get"), true)
        @Expect(gatewayActionIsReadOnly("config.schema.lookup"), true)
        @Expect(gatewayActionIsReadOnly("restart"), false)
    }

    @TestCase
    public func gatewayToolRecognizesAuthorizationRequirements(): Unit {
        @Expect(gatewayToolRequiresOwnerApproval("start"), true)
        @Expect(gatewayToolRequiresOwnerApproval("stop"), true)
        @Expect(gatewayToolRequiresOwnerApproval("restart"), true)
        @Expect(gatewayToolRequiresOwnerApproval("master_on"), true)
        @Expect(gatewayToolRequiresOwnerApproval("master_off"), true)
        @Expect(gatewayToolRequiresOwnerApproval("config.patch"), true)
        @Expect(gatewayToolRequiresOwnerApproval("config.apply"), true)
        @Expect(gatewayToolRequiresOwnerApproval("update.run"), true)
        @Expect(gatewayToolRequiresOwnerApproval("status"), false)

        @Expect(gatewayToolRequiresExplicitRequestApproval("config.patch"), true)
        @Expect(gatewayToolRequiresExplicitRequestApproval("config.apply"), true)
        @Expect(gatewayToolRequiresExplicitRequestApproval("update.run"), true)
        @Expect(gatewayToolRequiresExplicitRequestApproval("restart"), false)
    }

    @TestCase
    public func gatewayToolAutoOwnerApprovalOnlyAppliesToOperatorSurfaces(): Unit {
        @Expect(gatewayToolAutoOwnerApprovedForSource("cli"), true)
        @Expect(gatewayToolAutoOwnerApprovedForSource("control-ui"), true)
        @Expect(gatewayToolAutoOwnerApprovedForSource("dashboard"), true)
        @Expect(gatewayToolAutoOwnerApprovedForSource("cron"), true)
        @Expect(gatewayToolAutoOwnerApprovedForSource("gateway-rpc"), false)
        @Expect(gatewayToolAutoOwnerApprovedForSource("feishu"), false)
    }

    @TestCase
    public func gatewayToolRuntimeContextCanElevateOwnerByOperatorScope(): Unit {
        let context = GatewayToolRuntimeContext(
            "gateway-rpc",
            declaredUser: "operator:alice",
            operatorScopes: ["operator.admin"],
            prompt: "restart gateway"
        )
        @Expect(gatewayToolAutoOwnerApprovedForRuntimeContext(context), true)
    }

    @TestCase
    public func gatewayToolCanInferExplicitRequestsFromPrompt(): Unit {
        @Expect(gatewayToolInfersExplicitRequestFromPrompt("restart", "please restart gateway"), true)
        @Expect(gatewayToolInfersExplicitRequestFromPrompt("config.apply", "请应用配置到 gateway.auth.mode", path: Some("gateway.auth.mode")), true)
        @Expect(gatewayToolInfersExplicitRequestFromPrompt("update.run", "help me update metis"), true)
        @Expect(gatewayToolInfersExplicitRequestFromPrompt("config.apply", "show gateway status", path: Some("gateway.auth.mode")), false)
    }

    @TestCase
    public func gatewayToolDeniedActionJsonUsesDenyWithReasonContract(): Unit {
        let denied = gatewayToolDeniedActionJson(
            "config.apply",
            reasonCode: Some("owner_required"),
            ownerApproved: false,
            explicitRequest: false,
            path: Some("gateway.session.dmScope"),
            raw: Some("main")
        )
        @Expect(gatewayToolsetTestString(denied, "status"), "denied")
        @Expect(gatewayToolsetTestString(denied, "action"), "config.apply")
        @Expect(gatewayToolsetTestString(denied, "rejectionContract"), "deny-with-reason")
        @Expect(gatewayToolsetTestString(denied, "reasonCode"), "owner_required")
        @Expect(gatewayToolsetTestString(denied, "path"), "gateway.session.dmScope")
        @Expect(gatewayToolsetTestString(denied, "raw"), "main")
        @Expect(gatewayToolsetTestString(denied, "error").contains("authorization guard"), true)
    }

    @TestCase
    public func gatewayToolAuthorizationFailureJsonUsesOwnerAndExplicitRequestReasons(): Unit {
        let ownerDenied = gatewayToolAuthorizationFailureJson("restart").getOrThrow()
        @Expect(gatewayToolsetTestString(ownerDenied, "reasonCode"), "owner_required")
        @Expect(gatewayToolsetTestString(ownerDenied, "error").contains("owner approval"), true)

        let explicitDenied = gatewayToolAuthorizationFailureJson(
            "config.apply",
            ownerApproved: true,
            explicitRequest: false,
            path: Some("gateway"),
            raw: Some("{\"enabled\":true}")
        ).getOrThrow()
        @Expect(gatewayToolsetTestString(explicitDenied, "reasonCode"), "explicit_request_required")
        @Expect(gatewayToolsetTestString(explicitDenied, "error").contains("explicit user request"), true)
        @Expect(gatewayToolAuthorizationFailureJson("config.apply", ownerApproved: true, explicitRequest: true).isNone(), true)
    }

    @TestCase
    public func gatewayToolProtectsSensitiveConfigPaths(): Unit {
        @Expect(gatewayConfigPathIsProtected("gateway.controlUi.allowInsecureAuth"), true)
        @Expect(gatewayConfigPathIsProtected("gateway.auth.mode"), true)
        @Expect(gatewayConfigPathIsProtected("gateway.feishu.appId"), false)

        let denied = gatewayToolDeniedActionJson(
            "config.apply",
            errorMessage: Some("Gateway action `config.apply` cannot modify protected config path `gateway.controlUi.allowInsecureAuth` on the unified Gateway main runtime."),
            reasonCode: Some("protected_path"),
            ownerApproved: true,
            explicitRequest: true,
            path: Some("gateway.controlUi.allowInsecureAuth"),
            raw: Some("true")
        )
        @Expect(gatewayToolsetTestString(denied, "reasonCode"), "protected_path")
        @Expect(gatewayToolsetTestString(denied, "error").contains("protected config path"), true)
    }

    @TestCase
    public func gatewayToolAutoApprovesCliOwnerButStillRequiresExplicitMutationRequest(): Unit {
        let context = GatewayToolRuntimeContext("cli", channelName: "cli", prompt: "show gateway status")
        @Expect(gatewayToolAutoOwnerApprovedForRuntimeContext(context), true)
        @Expect(
            gatewayToolInfersExplicitRequestFromPrompt("config.apply", context.prompt, path: Some("gateway.auth.mode")),
            false
        )
        let denied = gatewayToolAuthorizationFailureJson(
            "config.apply",
            ownerApproved: gatewayToolAutoOwnerApprovedForRuntimeContext(context),
            explicitRequest: gatewayToolInfersExplicitRequestFromPrompt("config.apply", context.prompt, path: Some("gateway.auth.mode")),
            path: Some("gateway.auth.mode"),
            raw: Some("\"token\"")
        ).getOrThrow()
        @Expect(gatewayToolsetTestString(denied, "reasonCode"), "explicit_request_required")
    }

    @TestCase
    public func gatewayToolAutoContextAllowsCliMutationRequestButStillProtectsSensitivePath(): Unit {
        let context = GatewayToolRuntimeContext("cli", channelName: "cli", prompt: "请应用配置到 gateway.auth.mode")
        @Expect(gatewayToolAutoOwnerApprovedForRuntimeContext(context), true)
        @Expect(
            gatewayToolInfersExplicitRequestFromPrompt("config.apply", context.prompt, path: Some("gateway.auth.mode")),
            true
        )
        let denied = gatewayToolDeniedActionJson(
            "config.apply",
            errorMessage: Some("Gateway action `config.apply` cannot modify protected config path `gateway.auth.mode` on the unified Gateway main runtime."),
            reasonCode: Some("protected_path"),
            ownerApproved: gatewayToolAutoOwnerApprovedForRuntimeContext(context),
            explicitRequest: true,
            path: Some("gateway.auth.mode"),
            raw: Some("\"token\"")
        )
        @Expect(gatewayToolsetTestString(denied, "reasonCode"), "protected_path")
    }

    @TestCase
    public func gatewayToolChannelContextStaysNonOwnerByDefault(): Unit {
        let context = GatewayToolRuntimeContext("feishu", channelName: "feishu", senderId: "ou_123", prompt: "重启网关")
        @Expect(gatewayToolAutoOwnerApprovedForRuntimeContext(context), false)
        let denied = gatewayToolAuthorizationFailureJson("restart").getOrThrow()
        @Expect(gatewayToolsetTestString(denied, "reasonCode"), "owner_required")
    }

    @TestCase
    public func gatewayToolGatewayRpcContextUsesOperatorScopeAsOwnerSignal(): Unit {
        let context = GatewayToolRuntimeContext(
            "gateway-rpc",
            channelName: "gateway-rpc",
            declaredUser: "operator:bob",
            operatorScopes: ["operator.admin"],
            prompt: "restart gateway"
        )
        @Expect(gatewayToolAutoOwnerApprovedForRuntimeContext(context), true)
        @Expect(gatewayToolAuthorizationFailureJson("restart", ownerApproved: true).isNone(), true)
    }
}
