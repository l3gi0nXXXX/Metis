package metis.gateway.runtime

import metis.gateway.openclaw_channel.*
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

private func openClawChannelOk(status: String): JsonObject {
    let out = JsonObject()
    out.put("ok", true.toJsonValue())
    out.put("status", JsonString(status))
    return out
}

private func openClawChannelJstr(o: JsonObject, key: String): String {
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

        runner.enqueue(openClawChannelOk("started"))
        adapters[0].start()
        @Expect(runner.methods[0], OPENCLAW_CHANNEL_START_METHOD)
        @Expect(openClawChannelJstr(runner.payloads[0], "accountId"), "acct-a")

        let inbound = JsonObject()
        inbound.put("accountId", JsonString("acct-a"))
        inbound.put("messageId", JsonString("m-1"))
        inbound.put("peerId", JsonString("room-1"))
        inbound.put("senderId", JsonString("user-1"))
        inbound.put("text", JsonString("hello"))
        inbound.put("chatType", JsonString("group"))
        let messages = JsonArray([])
        messages.add(inbound)
        let pull = openClawChannelOk("ok")
        pull.put("messages", messages)
        runner.enqueue(pull)
        let pulled = adapters[0].pullInbound()
        @Expect(runner.methods[1], OPENCLAW_CHANNEL_PULL_INBOUND_METHOD)
        @Expect(pulled.size, 1)
        @Expect(pulled[0].accountId, "acct-a")
        @Expect(chatTypeToString(pulled[0].chatType), "group")

        let send = openClawChannelOk("sent")
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
        runner.enqueue(openClawChannelOk("healthy"))
        let capability = OpenClawChannelCapability("dingtalk", "dingtalk", ["main"], runner)

        let health = openClawChannelHealth(capability, "main")

        @Expect(health.ok, true)
        @Expect(runner.methods[0], OPENCLAW_CHANNEL_HEALTH_METHOD)
        @Expect(openClawChannelJstr(runner.payloads[0], "channelId"), "dingtalk")
        @Expect(runner.payloads[0].get("token").isNone(), true)
        @Expect(runner.payloads[0].get("configPath").isNone(), true)
    }

    @TestCase
    public func hostCapturedRepresentativeChannelsAutoRegisterAndBridgeGatewayLoop(): Unit {
        let runner = FakeOpenClawChannelRunner()
        let channels = JsonArray([])
        for (channelId in ["openclaw-weixin", "dingtalk", "feishu", "qqbot"]) {
            let spec = JsonObject()
            spec.put("id", JsonString(channelId))
            let accounts = JsonArray([])
            accounts.add(JsonString("${channelId}:acct-a"))
            accounts.add(JsonString("${channelId}:acct-b"))
            spec.put("accountIds", accounts)
            let row = JsonObject()
            row.put("pluginId", JsonString(channelId))
            row.put("id", JsonString(channelId))
            row.put("spec", spec)
            channels.add(row)
        }
        let capabilities = JsonObject()
        capabilities.put("channels", channels)
        let capture = JsonObject()
        capture.put("capabilities", capabilities)

        let registered = registerOpenClawCapturedChannelPlugins(capture, runner)

        @Expect(registered, 4)
        for (channelId in ["openclaw-weixin", "dingtalk", "feishu", "qqbot"]) {
            let plugin = GatewayChannelPluginRegistry.getById(channelId).getOrThrow()
            let adapters = plugin.createAdapters(JsonObject())
            @Expect(adapters.size, 2)

            runner.enqueue(openClawChannelOk("started"))
            adapters[0].start()

            let raw = JsonObject()
            raw.put("platform", JsonString(channelId))
            raw.put("rawEventId", JsonString("raw-${channelId}"))
            let media = JsonArray([])
            let mediaRef = JsonObject()
            mediaRef.put("kind", JsonString("image"))
            mediaRef.put("mediaId", JsonString("media-${channelId}"))
            media.add(mediaRef)
            let inbound = JsonObject()
            inbound.put("accountId", JsonString("${channelId}:acct-a"))
            inbound.put("messageId", JsonString("msg-${channelId}"))
            inbound.put("peerId", JsonString("room-${channelId}"))
            inbound.put("senderId", JsonString("user-${channelId}"))
            inbound.put("text", JsonString("hello ${channelId}"))
            inbound.put("chatType", JsonString("group"))
            inbound.put("threadId", JsonString("thread-${channelId}"))
            inbound.put("replyToMessageId", JsonString("reply-${channelId}"))
            inbound.put("mediaRefs", media)
            inbound.put("rawMetadata", raw)
            let messages = JsonArray([])
            messages.add(inbound)
            let pull = openClawChannelOk("ok")
            pull.put("messages", messages)
            runner.enqueue(pull)
            let pulled = adapters[0].pullInbound()
            @Expect(pulled.size, 1)
            @Expect(pulled[0].accountId, "${channelId}:acct-a")
            @Expect(pulled[0].threadId.getOrThrow(), "thread-${channelId}")
            @Expect(pulled[0].replyTargetMessageId.getOrThrow(), "reply-${channelId}")
            @Expect(pulled[0].mediaContext.toJsonString().contains("media-${channelId}"), true)
            @Expect(pulled[0].raw.getOrThrow().contains("raw-${channelId}"), true)

            let send = openClawChannelOk("sent")
            send.put("messageId", JsonString("out-${channelId}"))
            runner.enqueue(send)
            let sent = adapters[0].sendWithMessageId(
                OutboundMessage(
                    ChannelType.Extension(channelId),
                    "room-${channelId}",
                    "reply ${channelId}",
                    replyToMessageId: Some("msg-${channelId}"),
                    replyInThread: true,
                    accountId: "${channelId}:acct-a"
                )
            )
            @Expect(sent, "out-${channelId}")
        }
    }

    @TestCase
    public func hostRegistryEnvelopeChannelsAutoRegisterFromGatewayRegistries(): Unit {
        let runner = FakeOpenClawChannelRunner()
        let channels = JsonArray([])
        let channel = JsonObject()
        channel.put("pluginId", JsonString("openclaw-weixin"))
        channel.put("id", JsonString("weixin"))
        let spec = JsonObject()
        spec.put("channelId", JsonString("weixin"))
        let accounts = JsonArray([])
        accounts.add(JsonString("wx-a"))
        accounts.add(JsonString("wx-b"))
        spec.put("accountIds", accounts)
        channel.put("spec", spec)
        channels.add(channel)
        let gatewayRegistries = JsonObject()
        gatewayRegistries.put("channels", channels)
        let capture = JsonObject()
        capture.put("gatewayRegistries", gatewayRegistries)

        let registered = registerOpenClawCapturedChannelPlugins(capture, runner)

        @Expect(registered, 1)
        let plugin = GatewayChannelPluginRegistry.getById("openclaw-weixin").getOrThrow()
        let adapters = plugin.createAdapters(JsonObject())
        @Expect(plugin.declaredChannelIds()[0], "weixin")
        @Expect(adapters.size, 2)
    }
}
