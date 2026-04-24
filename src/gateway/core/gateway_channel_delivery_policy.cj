package metis.gateway.core

import metis.core.config.GatewayUserSettings
import std.collection.ArrayList

private func gatewayCoreNormalizedChannelId(channelId: String): String {
    channelId.trimAscii().toAsciiLower()
}

private func gatewayCoreChannelSupportsReplyInThread(user: GatewayUserSettings, channelId: String): Bool {
    let normalized = gatewayCoreNormalizedChannelId(channelId)
    if (normalized == "feishu") {
        return true
    }
    if (normalized == "qq") {
        return false
    }
    return true
}

private func gatewayCoreChannelSupportsMessageReply(user: GatewayUserSettings, channelId: String): Bool {
    let normalized = gatewayCoreNormalizedChannelId(channelId)
    if (normalized == "feishu" || normalized == "qq") {
        return true
    }
    return true
}

public func gatewayCorePromptRuntimeCapabilities(user: GatewayUserSettings, channelId: String): Array<String> {
    let normalized = gatewayCoreNormalizedChannelId(channelId)
    let out = ArrayList<String>()
    if (gatewayCoreChannelSupportsMessageReply(user, normalized)) {
        out.add("message-reply")
    }
    if (gatewayCoreChannelSupportsReplyInThread(user, normalized)) {
        out.add("thread-reply")
    }
    if (normalized == "webchat") {
        out.add("native-approval-ui")
        out.add("inlinebuttons")
    }
    out.toArray()
}

public func gatewayApplyOutboundChannelPolicy(
    user: GatewayUserSettings,
    channelId: String,
    replyToMessageId: Option<String>,
    replyInThread: Bool
): (Option<String>, Bool, Bool, String) {
    let messageReplySupported = gatewayCoreChannelSupportsMessageReply(user, channelId)
    let threadReplySupported = gatewayCoreChannelSupportsReplyInThread(user, channelId)
    let effectiveReplyToMessageId = if (!messageReplySupported) {
        None<String>
    } else {
        replyToMessageId
    }
    let effectiveReplyInThread = if (threadReplySupported) {
        replyInThread
    } else {
        false
    }
    let degraded = (replyToMessageId != None && !messageReplySupported) || (replyInThread && !threadReplySupported)
    let reason = if (replyToMessageId != None && !messageReplySupported) {
        "message-reply-unsupported"
    } else if (replyInThread && !threadReplySupported) {
        "thread-reply-unsupported"
    } else {
        "ok"
    }
    (effectiveReplyToMessageId, effectiveReplyInThread, degraded, reason)
}
