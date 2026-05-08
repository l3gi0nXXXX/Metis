package metis.gateway.openclaw_channel_http

import metis.gateway.model.{ChannelType, OutboundMessage, chatTypeToString}

import magic.jsonable.*
import std.collection.ArrayList
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

private class FakeOpenClawRunner <: OpenClawBridgeRunner {
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

private func jstr(o: JsonObject, key: String): String {
    match (o.get(key)) {
        case Some(v) => try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func jint(o: JsonObject, key: String): Int64 {
    match (o.get(key)) {
        case Some(v) => try { v.asInt().getValue() } catch (_e: Exception) { 0 }
        case None => 0
    }
}

private func jobj(o: JsonObject, key: String): JsonObject {
    match (o.get(key)) {
        case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func jarr(o: JsonObject, key: String): JsonArray {
    match (o.get(key)) {
        case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func okResponse(status: String): JsonObject {
    let out = JsonObject()
    out.put("ok", true.toJsonValue())
    out.put("status", JsonString(status))
    return out
}

@Test
public class OpenClawChannelHttpBridgeTest {
    @TestCase
    public func channelAdapterSendsTextThroughStructuredRunnerPayload(): Unit {
        let runner = FakeOpenClawRunner()
        let response = okResponse("sent")
        response.put("messageId", JsonString("out-42"))
        runner.enqueue(response)

        let bridge = OpenClawChannelAdapterBridge("demo", "acct-1", runner)
        let sentId = bridge.sendWithMessageId(
            OutboundMessage(
                ChannelType.Extension("demo"),
                "peer-1",
                "hello from metis",
                replyToMessageId: Some("in-41"),
                accountId: "acct-1"
            )
        )

        @Expect(sentId, "out-42")
        @Expect(runner.methods[0], OPENCLAW_CHANNEL_SEND_METHOD)
        let payload = runner.payloads[0]
        @Expect(jstr(payload, "channelId"), "demo")
        @Expect(jstr(payload, "accountId"), "acct-1")
        @Expect(jstr(payload, "peerId"), "peer-1")
        @Expect(jstr(payload, "text"), "hello from metis")
        @Expect(jstr(payload, "replyToMessageId"), "in-41")
        @Expect(jstr(payload, "chatType"), "direct")
    }

    @TestCase
    public func channelPullPreservesMediaThreadChatTypeAndRawMetadata(): Unit {
        let runner = FakeOpenClawRunner()
        let media = JsonArray([])
        let image = JsonObject()
        image.put("kind", JsonString("photo"))
        image.put("mediaId", JsonString("media-1"))
        image.put("mimeType", JsonString("image/png"))
        image.put("fileName", JsonString("diagram.png"))
        media.add(image)

        let raw = JsonObject()
        raw.put("platform", JsonString("openclaw"))
        raw.put("messageType", JsonString("image"))

        let inbound = JsonObject()
        inbound.put("accountId", JsonString("acct-2"))
        inbound.put("messageId", JsonString("msg-7"))
        inbound.put("peerId", JsonString("chat-9"))
        inbound.put("senderId", JsonString("user-3"))
        inbound.put("text", JsonString("see attached"))
        inbound.put("chatType", JsonString("group"))
        inbound.put("threadId", JsonString("topic-4"))
        inbound.put("replyToMessageId", JsonString("root-1"))
        inbound.put("mentioned", true.toJsonValue())
        inbound.put("mediaRefs", media)
        inbound.put("rawMetadata", raw)

        let messages = JsonArray([])
        messages.add(inbound)
        let response = okResponse("ok")
        response.put("messages", messages)
        runner.enqueue(response)

        let bridge = OpenClawChannelAdapterBridge("demo", "acct-2", runner)
        let pulled = bridge.pullInbound()

        @Expect(pulled.size, 1)
        @Expect(pulled[0].accountId, "acct-2")
        @Expect(pulled[0].peerId, "chat-9")
        @Expect(chatTypeToString(pulled[0].chatType), "group")
        @Expect(pulled[0].threadId.getOrThrow(), "topic-4")
        @Expect(pulled[0].replyTargetMessageId.getOrThrow(), "root-1")
        @Expect(jstr(pulled[0].mediaContext, "schema"), "openclaw.channel_http.v1")
        @Expect(jarr(pulled[0].mediaContext, "mediaRefs").size(), 1)
        @Expect(jstr(jobj(pulled[0].mediaContext, "rawMetadata"), "messageType"), "image")
    }

    @TestCase
    public func httpRouteDispatchBuildsRequestAndParsesSuccessfulResponse(): Unit {
        let runner = FakeOpenClawRunner()
        let headers = JsonObject()
        headers.put("content-type", JsonString("application/json"))
        let response = okResponse("ok")
        response.put("statusCode", 201.toJsonValue())
        response.put("headers", headers)
        response.put("body", JsonString("{\"created\":true}"))
        runner.enqueue(response)

        let query = JsonObject()
        query.put("a", JsonString("1"))
        let requestHeaders = JsonObject()
        requestHeaders.put("x-test", JsonString("yes"))
        let bridge = OpenClawHttpRouteBridge(runner)
        let result = bridge.dispatch(
            "POST",
            "/webhook/demo",
            query: query,
            headers: requestHeaders,
            body: JsonString("{\"hello\":\"world\"}"),
            timeoutMs: 2500
        )

        @Expect(runner.methods[0], OPENCLAW_HTTP_DISPATCH_METHOD)
        let payload = runner.payloads[0]
        @Expect(jstr(payload, "method"), "POST")
        @Expect(jstr(payload, "path"), "/webhook/demo")
        @Expect(jstr(jobj(payload, "query"), "a"), "1")
        @Expect(jstr(jobj(payload, "headers"), "x-test"), "yes")
        @Expect(jint(payload, "timeoutMs"), 2500)
        @Expect(result.ok, true)
        @Expect(result.statusCode, 201)
        @Expect(jstr(result.headers, "content-type"), "application/json")
        @Expect(result.body, "{\"created\":true}")
    }

    @TestCase
    public func httpParserPreservesHandlerErrorAndTimeoutDiagnostics(): Unit {
        let handler = JsonObject()
        handler.put("ok", false.toJsonValue())
        handler.put("status", JsonString("error"))
        let handlerDiag = JsonObject()
        handlerDiag.put("kind", JsonString("handler_error"))
        handlerDiag.put("message", JsonString("boom"))
        handler.put("diagnostic", handlerDiag)

        let timeout = JsonObject()
        timeout.put("ok", false.toJsonValue())
        timeout.put("status", JsonString("timeout"))
        let timeoutDiag = JsonObject()
        timeoutDiag.put("kind", JsonString("timeout"))
        timeoutDiag.put("message", JsonString("handler exceeded timeout"))
        timeoutDiag.put("timeoutMs", 3000.toJsonValue())
        timeout.put("diagnostic", timeoutDiag)

        let handlerResult = openClawParseHttpDispatchResult(handler)
        let timeoutResult = openClawParseHttpDispatchResult(timeout)

        @Expect(handlerResult.ok, false)
        @Expect(handlerResult.diagnosticKind, "handler_error")
        @Expect(handlerResult.diagnosticMessage, "boom")
        @Expect(timeoutResult.ok, false)
        @Expect(timeoutResult.status, "timeout")
        @Expect(timeoutResult.diagnosticKind, "timeout")
        @Expect(jint(timeoutResult.diagnostic, "timeoutMs"), 3000)
    }

    @TestCase
    public func bridgeUsesFakeRunnerWithoutTokenOrRealConfigAccess(): Unit {
        let runner = FakeOpenClawRunner()
        runner.enqueue(okResponse("healthy"))

        let bridge = OpenClawChannelAdapterBridge("demo", "", runner)
        let health = bridge.health()

        @Expect(health.ok, true)
        @Expect(runner.methods[0], OPENCLAW_CHANNEL_HEALTH_METHOD)
        let payload = runner.payloads[0]
        @Expect(jstr(payload, "accountId"), "")
        @Expect(payload.get("token").isNone(), true)
        @Expect(payload.get("configPath").isNone(), true)
    }
}
