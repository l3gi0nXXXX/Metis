package metis.gateway.core

import metis.core.config.GatewayUserSettings

import magic.jsonable.*
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonObject, JsonString}

@Test
public class GatewayTelegramErrorPolicyTest {
    @TestCase
    public func defaultsToAlwaysAndFallbackCooldown(): Unit {
        var user = GatewayUserSettings()
        user.telegram.errorPolicy.policy = "unknown"
        user.telegram.errorPolicy.cooldownMs = 0
        @Expect(gatewayTelegramErrorPolicyMode(user), "always")
        @Expect(gatewayTelegramErrorCooldownMs(user), 60000)
    }

    @TestCase
    public func alwaysPolicyRepliesEveryTime(): Unit {
        var user = GatewayUserSettings()
        user.telegram.errorPolicy.policy = "always"
        user.telegram.errorPolicy.cooldownMs = 1000
        let state = GatewayTelegramErrorPolicyState()
        @Expect(state.shouldReply(user, "chat-1", "topic-1", "gateway-execution", 1000), true)
        @Expect(state.shouldReply(user, "chat-1", "topic-1", "gateway-execution", 1001), true)
    }

    @TestCase
    public func silentPolicySuppressesEveryTime(): Unit {
        var user = GatewayUserSettings()
        user.telegram.errorPolicy.policy = "silent"
        let state = GatewayTelegramErrorPolicyState()
        @Expect(state.shouldReply(user, "chat-1", "topic-1", "gateway-execution", 1000), false)
        @Expect(state.shouldReply(user, "chat-1", "topic-1", "gateway-execution", 70000), false)
    }

    @TestCase
    public func legacySilentErrorRepliesFlagSuppressesPolicy(): Unit {
        var user = GatewayUserSettings()
        user.telegram.errorPolicy.policy = "always"
        user.telegram.errorPolicy.silentErrorReplies = true
        @Expect(gatewayTelegramErrorPolicyMode(user), "silent")
        let state = GatewayTelegramErrorPolicyState()
        @Expect(state.shouldReply(user, "chat-1", "topic-1", "gateway-execution", 1000), false)
    }

    @TestCase
    public func oncePolicyUsesCooldownPerPeerThreadAndErrorKey(): Unit {
        var user = GatewayUserSettings()
        user.telegram.errorPolicy.policy = "once"
        user.telegram.errorPolicy.cooldownMs = 1000
        let state = GatewayTelegramErrorPolicyState()

        @Expect(state.shouldReply(user, "chat-1", "topic-1", "gateway-execution", 1000), true)
        @Expect(state.shouldReply(user, "chat-1", "topic-1", "gateway-execution", 1500), false)
        @Expect(state.shouldReply(user, "chat-1", "topic-1", "gateway-execution", 2000), true)

        @Expect(state.shouldReply(user, "chat-2", "topic-1", "gateway-execution", 1500), true)
        @Expect(state.shouldReply(user, "chat-1", "topic-2", "gateway-execution", 1500), true)
        @Expect(state.shouldReply(user, "chat-1", "topic-1", "delivery", 1500), true)
    }

    @TestCase
    public func routeLevelErrorPolicyOverridesGlobalPolicy(): Unit {
        var user = GatewayUserSettings()
        user.telegram.errorPolicy.policy = "always"
        let groups = JsonObject()
        let group = JsonObject()
        let topics = JsonObject()
        let topic = JsonObject()
        let topicPolicy = JsonObject()
        topicPolicy.put("policy", JsonString("silent"))
        topic.put("errorPolicy", topicPolicy)
        topics.put("42", topic)
        group.put("topics", topics)
        let groupPolicy = JsonObject()
        groupPolicy.put("policy", JsonString("once"))
        groupPolicy.put("cooldownMs", 10.toJsonValue())
        group.put("errorPolicy", groupPolicy)
        groups.put("-100", group)
        user.telegram.groups = Some(groups)

        @Expect(gatewayTelegramErrorPolicyModeForTarget(user, "group:-100:topic:42", "42"), "silent")
        @Expect(gatewayTelegramErrorPolicyModeForTarget(user, "group:-100:topic:7", "7"), "once")
        @Expect(gatewayTelegramErrorCooldownMsForTarget(user, "group:-100:topic:7", "7"), 10)
        @Expect(gatewayTelegramErrorPolicyModeForTarget(user, "group:-200", ""), "always")
    }

    @TestCase
    public func directErrorPolicyCanSuppressOnePeerOnly(): Unit {
        var user = GatewayUserSettings()
        user.telegram.errorPolicy.policy = "always"
        let direct = JsonObject()
        let peer = JsonObject()
        let policy = JsonObject()
        policy.put("policy", JsonString("silent"))
        peer.put("errorPolicy", policy)
        direct.put("user:8734062810", peer)
        user.telegram.direct = Some(direct)
        let state = GatewayTelegramErrorPolicyState()

        @Expect(state.shouldReply(user, "user:8734062810", "", "gateway-execution", 1000), false)
        @Expect(state.shouldReply(user, "user:123", "", "gateway-execution", 1000), true)
    }
}
