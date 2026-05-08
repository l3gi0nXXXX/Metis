package metis.gateway.openclaw_channel

import magic.jsonable.*
import metis.gateway.config.GatewayChannelPluginRegistry
import metis.gateway.model.{ChannelType, OutboundMessage, chatTypeToString}
import metis.gateway.openclaw_channel_http.{OPENCLAW_CHANNEL_HEALTH_METHOD, OPENCLAW_CHANNEL_PULL_INBOUND_METHOD, OPENCLAW_CHANNEL_SEND_METHOD, OPENCLAW_CHANNEL_START_METHOD, OpenClawBridgeRunner}

import std.collection.ArrayList
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

private class FakeOpenClawChannelRunner <: OpenClawBridgeRunner {
    public let methods = ArrayList<String>()
    public let payloads = ArrayList<JsonObject>()
    private let responses = ArrayList<JsonObject>()

    public func enqueue(response: JsonObject): Unit {
        this.responses.add(response)
    }

    public func invoke(method: String, payload: JsonObject): JsonObject {
        this.methods.add(method)
        this.payloads.add(payload)
        if (this.responses.size == 0) {
            let out = JsonObject()
            out.put("ok", false.toJsonValue())
            out.put("status", JsonString("missing_fake_response"))
            return out
        }
        let response = this.responses[0]
        this.responses.remove(at: 0)
        response
    }
}

private func okChannel(status: String): JsonObject {
    let out = JsonObject()
    out.put("ok", true.toJsonValue())
    out.put("status", JsonString(status))
    return out
}

private func jstr(o: JsonObject, key: String): String {
    match (o.get(key)) {
        case Some(v) => try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
}

@Test
public class OpenClawChannelAdapterTest {
    @TestCase
    public func registerChannelCaptureCreatesGatewayPluginAndAdaptersPerAccount(): Unit {
        let runner = FakeOpenClawChannelRunner()
        let meta = JsonObject()
        meta.put("label", JsonString("OpenClaw Weixin"))
        let capabilities = JsonObject()
        capabilities.put("reply", true.toJsonValue())
        let capability = OpenClawChannelCapability(
            "openclaw-weixin",
            "openclaw-weixin",
            ["acct-a", "acct-b"],
            runner,
            meta: meta,
            capabilities: capabilities
        )

        registerOpenClawChannelPlugin(capability)

        let plugin = GatewayChannelPluginRegistry.getById("openclaw-weixin").getOrThrow()
        @Expect(plugin.declaredChannelIds()[0], "openclaw-weixin")
        let adapters = plugin.createAdapters(JsonObject())
        @Expect(adapters.size, 2)
        @Expect(adapters[0].name, "openclaw-weixin")

        runner.enqueue(okChannel("started"))
        adapters[0].start()
        @Expect(runner.methods[0], OPENCLAW_CHANNEL_START_METHOD)
        @Expect(jstr(runner.payloads[0], "accountId"), "acct-a")

        let inbound = JsonObject()
        inbound.put("accountId", JsonString("acct-a"))
        inbound.put("messageId", JsonString("m-1"))
        inbound.put("peerId", JsonString("room-1"))
        inbound.put("senderId", JsonString("user-1"))
        inbound.put("text", JsonString("hello"))
        inbound.put("chatType", JsonString("group"))
        let messages = JsonArray([])
        messages.add(inbound)
        let pull = okChannel("ok")
        pull.put("messages", messages)
        runner.enqueue(pull)
        let pulled = adapters[0].pullInbound()
        @Expect(runner.methods[1], OPENCLAW_CHANNEL_PULL_INBOUND_METHOD)
        @Expect(pulled.size, 1)
        @Expect(pulled[0].accountId, "acct-a")
        @Expect(chatTypeToString(pulled[0].chatType), "group")

        let send = okChannel("sent")
        send.put("messageId", JsonString("out-1"))
        runner.enqueue(send)
        let sentId = adapters[0].sendWithMessageId(
            OutboundMessage(ChannelType.Extension("openclaw-weixin"), "room-1", "reply", accountId: "acct-a")
        )
        @Expect(runner.methods[2], OPENCLAW_CHANNEL_SEND_METHOD)
        @Expect(sentId, "out-1")
    }

    @TestCase
    public func channelHealthUsesGatewayOwnedAdapterPathWithoutSecrets(): Unit {
        let runner = FakeOpenClawChannelRunner()
        runner.enqueue(okChannel("healthy"))
        let capability = OpenClawChannelCapability("dingtalk", "dingtalk", ["main"], runner)

        let health = openClawChannelHealth(capability, "main")

        @Expect(health.ok, true)
        @Expect(runner.methods[0], OPENCLAW_CHANNEL_HEALTH_METHOD)
        @Expect(jstr(runner.payloads[0], "channelId"), "dingtalk")
        @Expect(runner.payloads[0].get("token").isNone(), true)
        @Expect(runner.payloads[0].get("configPath").isNone(), true)
    }
}
