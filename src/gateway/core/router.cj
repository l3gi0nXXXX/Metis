package metis.gateway.core

import metis.gateway.model.*
import metis.gateway.model.ChannelPolicyConfig
import metis.gateway.session.gatewayBuildChannelSessionKey

import std.collection.HashMap
import stdx.encoding.json.JsonObject

/**
 * Gateway 最小路由器（P0）。
 *
 * 职责：
 * 1) 做基础准入判断（空消息、私聊/群聊开关、allowlist、@mention）；
 * 2) 生成 conversationKey，供 AgentBridge 维护会话上下文；
 * 3) 返回 RouteDecision，供上层服务决定是否继续处理。
 */
public class GatewayRouter {
    private let policyByChannel: HashMap<String, ChannelPolicyConfig>
    /** 见 `GatewaySessionUserSettings.dmScope`：`per-chat` | `main` | `per-peer` | `per-channel-peer`。 */
    private let dmScope: String

    public init(policyByChannel: HashMap<String, ChannelPolicyConfig>, dmScope!: String = "per-chat") {
        this.policyByChannel = policyByChannel
        this.dmScope = normalizeDmScope(dmScope)
    }

    public func route(message: InboundMessage): RouteDecision {
        // 1. 文本为空直接拒绝，避免无效调用模型。
        if (message.text.trimAscii().isEmpty()) {
            return RouteDecision(false, "empty text")
        }
        let channelGateReason = gatewayChannelGateRejectionReason(message)
        if (!channelGateReason.isEmpty()) {
            return RouteDecision(false, channelGateReason)
        }

        let channelName = channelToString(message.channel)
        let policy = this.policyByChannel.get(channelName) ?? ChannelPolicyConfig()

        // 2. 聊天类型开关判断。
        match (message.chatType) {
            case ChatType.Direct =>
                if (!policy.enableDirect) {
                    return RouteDecision(false, "direct chat disabled")
                }
            case ChatType.Group =>
                if (!policy.enableGroup) {
                    return RouteDecision(false, "group chat disabled")
                }
                // P0 默认群聊需要 @，降低误触发风险。
                if (policy.requireMentionInGroup && !message.mentioned) {
                    return RouteDecision(false, "group message requires mention")
                }
        }

        // 3. sender allowlist 判断。
        // allowFrom 为空表示不做 sender 限制；包含 "*" 表示放行全部。
        if (!policy.allowFrom.isEmpty()) {
            var allowed = false
            for (id in policy.allowFrom) {
                if (id == "*" || id == message.senderId) {
                    allowed = true
                    break
                }
            }
            if (!allowed) {
                return RouteDecision(false, "sender not in allowFrom")
            }
        }

        // 4. 生成会话键（见 gateway.session.dmScope）。
        let conversationKey = this.buildConversationKey(message)
        return RouteDecision(true, "accepted", conversationKey: conversationKey)
    }

    /**
     * 按 `dmScope` 生成会话键；默认 `per-chat` 与早期 `channel:chatType:peerId` 一致。
     */
    private func buildConversationKey(message: InboundMessage): String {
        gatewayBuildChannelSessionKey(
            channelToString(message.channel),
            message.chatType,
            message.peerId,
            message.senderId,
            conversationId: message.conversationId ?? "",
            dmScope: this.dmScope
        )
    }
}

private func gatewayChannelGateRejectionReason(message: InboundMessage): String {
    let context = match (message.mediaContext.get("context")) {
        case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let gate = match (context.get("feishuGate")) {
        case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    if (gate.size() == 0) {
        return ""
    }
    let trigger = match (gate.get("triggerAgent")) {
        case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { true }
        case None => true
    }
    if (trigger) {
        return ""
    }
    match (gate.get("reason")) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "channel gate rejected" }
        case None => "channel gate rejected"
    }
}

private func normalizeDmScope(raw: String): String {
    let s = raw.trimAscii().toAsciiLower()
    if (s == "main" || s == "per-peer" || s == "per-channel-peer") {
        return s
    }
    "per-chat"
}
