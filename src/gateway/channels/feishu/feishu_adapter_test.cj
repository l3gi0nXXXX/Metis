package metis.gateway.channels.feishu

import metis.gateway.model.FeishuConfig
import std.unittest.testmacro.*

@Test
public class FeishuAdapterTest {
    @TestCase
    public func webhookThreadPayloadProjectsUnifiedImRouteContext(): Unit {
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true))
        adapter.start()
        let payload =
            "{" +
            "\"header\":{\"event_type\":\"im.message.receive_v1\"}," +
            "\"event\":{" +
            "\"sender\":{\"sender_id\":{\"open_id\":\"ou_123\"}}," +
            "\"message\":{" +
            "\"message_id\":\"om_1\"," +
            "\"chat_id\":\"oc_a\"," +
            "\"chat_type\":\"group\"," +
            "\"message_type\":\"text\"," +
            "\"content\":\"{\\\"text\\\":\\\"hello\\\"}\"," +
            "\"root_id\":\"\"," +
            "\"thread_id\":\"thread_x\"" +
            "}" +
            "}" +
            "}"

        @Expect(adapter.ingestWebhookPayload(payload).contains("\"ok\":true"), true)
        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].peerId, "oc_a")
        @Expect(inbound[0].threadId.getOrThrow(), "thread_x")
        let imRoute = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("imRoute").getOrThrow().asObject()
        @Expect(imRoute.get("channel").getOrThrow().asString().getValue(), "feishu")
        @Expect(imRoute.get("accountId").getOrThrow().asString().getValue(), "default")
        @Expect(imRoute.get("peerKind").getOrThrow().asString().getValue(), "thread")
        @Expect(imRoute.get("peerId").getOrThrow().asString().getValue(), "thread_x")
        @Expect(imRoute.get("parentPeerKind").getOrThrow().asString().getValue(), "group")
        @Expect(imRoute.get("parentPeerId").getOrThrow().asString().getValue(), "oc_a")
        @Expect(imRoute.get("senderId").getOrThrow().asString().getValue(), "ou_123")
        @Expect(imRoute.get("messageId").getOrThrow().asString().getValue(), "om_1")
    }
}
