package metis.gateway.core

import metis.core.config.GatewayUserSettings
import metis.gateway.model.{ChannelType, ChatType, InboundMessage}

import std.fs.{Directory, Path, remove}
import std.time.DateTime
import std.unittest.testmacro.*

private func withTelegramThreadBindingTestRoot<T>(block: () -> T): T {
    let root = Path("/tmp/metis-telegram-thread-binding-manager-test")
    try { remove(root, recursive: true) } catch (_e: Exception) { () }
    Directory.create(root, recursive: true)
    setGatewayTelegramThreadBindingRootForTest(Some(root))
    try {
        return block()
    } finally {
        setGatewayTelegramThreadBindingRootForTest(None<Path>)
        try { remove(root, recursive: true) } catch (_e: Exception) { () }
    }
}

@Test
public class GatewayTelegramThreadBindingManagerTest {
    @TestCase
    public func bindResolveTouchUnbindUsesDurableJsonStore(): Unit {
        withTelegramThreadBindingTestRoot {
            let bound = gatewayTelegramThreadBindingBind(
                "telegram",
                "default",
                "group:-100:topic:42",
                "agent:main:topic-review",
                parentConversationId: "group:-100",
                threadId: "42",
                ownerId: "8734062810",
                nowMs: 1000
            )
            @Expect(bound.get("status").getOrThrow().asString().getValue(), "bound")
            let resolved = gatewayTelegramThreadBindingResolve(
                "telegram",
                "default",
                "group:-100:topic:42",
                parentConversationId: "group:-100",
                nowMs: 1500
            )
            @Expect(resolved.get("sessionKey").getOrThrow().asString().getValue(), "agent:main:topic-review")
            let touched = gatewayTelegramThreadBindingTouch("telegram", "default", "group:-100:topic:42", nowMs: 2000)
            @Expect(touched.get("status").getOrThrow().asString().getValue(), "touched")
            @Expect(touched.get("binding").getOrThrow().asObject().get("updatedAtMs").getOrThrow().toJsonString(), "2000")
            let unbound = gatewayTelegramThreadBindingUnbind("telegram", "default", "group:-100:topic:42", nowMs: 2500)
            @Expect(unbound.get("status").getOrThrow().asString().getValue(), "unbound")
            @Expect(gatewayTelegramThreadBindingList(nowMs: 3000).size(), 0)
        }
    }

    @TestCase
    public func parentConversationFallbackAndExpirationAreDeterministic(): Unit {
        withTelegramThreadBindingTestRoot {
            let _ = gatewayTelegramThreadBindingBind(
                "telegram",
                "*",
                "group:-100",
                "agent:main:parent",
                ttlMs: 500,
                nowMs: 1000
            )
            let inherited = gatewayTelegramThreadBindingResolve(
                "telegram",
                "work",
                "group:-100:topic:7",
                parentConversationId: "group:-100",
                nowMs: 1200
            )
            @Expect(inherited.get("sessionKey").getOrThrow().asString().getValue(), "agent:main:parent")
            let expired = gatewayTelegramThreadBindingResolve(
                "telegram",
                "work",
                "group:-100:topic:7",
                parentConversationId: "group:-100",
                nowMs: 1600
            )
            @Expect(expired.size(), 0)
        }
    }

    @TestCase
    public func sessionHintResolverUsesTelegramOnlyWhenEnabled(): Unit {
        withTelegramThreadBindingTestRoot {
            let _ = gatewayTelegramThreadBindingBind(
                "telegram",
                "default",
                "user:8734062810",
                "agent:main:explicit:telegram-user",
                nowMs: 1000
            )
            let message = InboundMessage(
                ChannelType.Telegram,
                "m1",
                "user:8734062810",
                "8734062810",
                ChatType.Direct,
                "hello",
                false,
                DateTime.now(),
                conversationId: Some("user:8734062810"),
                accountId: "default"
            )
            var user = GatewayUserSettings()
            @Expect(gatewayTelegramThreadBindingSessionHintForMessage(user, message, "default"), "")
            user.telegram.threadBindings.enabled = true
            @Expect(gatewayTelegramThreadBindingSessionHintForMessage(user, message, "default"), "agent:main:explicit:telegram-user")
        }
    }
}
