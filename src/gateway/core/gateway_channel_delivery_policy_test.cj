package metis.gateway.core

import metis.core.config.GatewayUserSettings

import std.unittest.testmacro.*

@Test
public class GatewayChannelDeliveryPolicyTest {
    @TestCase
    public func qqThreadReplyFallsBackToMessageReply(): Unit {
        let (replyToMessageId, replyInThread, degraded, reason) = gatewayApplyOutboundChannelPolicy(
            GatewayUserSettings(),
            "qq",
            Some("msg-1"),
            true
        )
        @Expect(replyToMessageId.getOrThrow(), "msg-1")
        @Expect(replyInThread, false)
        @Expect(degraded, true)
        @Expect(reason, "thread-reply-unsupported")
    }

    @TestCase
    public func feishuThreadReplyStaysEnabled(): Unit {
        let (replyToMessageId, replyInThread, degraded, reason) = gatewayApplyOutboundChannelPolicy(
            GatewayUserSettings(),
            "feishu",
            Some("msg-2"),
            true
        )
        @Expect(replyToMessageId.getOrThrow(), "msg-2")
        @Expect(replyInThread, true)
        @Expect(degraded, false)
        @Expect(reason, "ok")
    }

    @TestCase
    public func webchatPromptCapabilitiesExposeNativeApprovalUi(): Unit {
        let caps = gatewayCorePromptRuntimeCapabilities(GatewayUserSettings(), "webchat")
        @Expect(caps.contains("native-approval-ui"), true)
        @Expect(caps.contains("inlinebuttons"), true)
        @Expect(caps.contains("message-reply"), true)
        @Expect(caps.contains("thread-reply"), true)
    }

    @TestCase
    public func qqPromptCapabilitiesReflectThreadReplyLimits(): Unit {
        let caps = gatewayCorePromptRuntimeCapabilities(GatewayUserSettings(), "qq")
        @Expect(caps.contains("message-reply"), true)
        @Expect(caps.contains("thread-reply"), false)
        @Expect(caps.contains("native-approval-ui"), false)
    }
}
