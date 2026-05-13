package metis.gateway.runtime

import metis.gateway.openclaw_http.*
import magic.jsonable.*
import metis.gateway.openclaw_channel_http.{OPENCLAW_HTTP_DISPATCH_METHOD, OpenClawBridgeRunner}

import std.collection.ArrayList
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

private class FakeOpenClawHttpRunner <: OpenClawBridgeRunner {
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

private func openClawHttpOk(statusCode: Int64, body: String): JsonObject {
    let out = JsonObject()
    out.put("ok", true.toJsonValue())
    out.put("status", JsonString("ok"))
    out.put("statusCode", statusCode.toJsonValue())
    out.put("headers", JsonObject())
    out.put("body", JsonString(body))
    return out
}

private func openClawHttpJstr(o: JsonObject, key: String): String {
    match (o.get(key)) {
        case Some(v) => try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
}

@Test
public class OpenClawHttpDispatcherTest {
    @TestCase
    public func dispatcherRoutesWechatStyleWebhooksThroughGatewayRegistry(): Unit {
        OpenClawHttpRouteRegistry.clearForTest()
        let runner = FakeOpenClawHttpRunner()
        for (path in ["/webhook/wechat-mp", "/webhook/wecom", "/webhook/wecom-app", "/webhook/wecom-kf"]) {
            runner.enqueue(openClawHttpOk(200, "{\"accepted\":true}"))
            let registered = OpenClawHttpRouteRegistry.register(
                OpenClawHttpRouteRegistration("wechat-suite", "POST", path, runner, maxBodyBytes: 1024, timeoutMs: 1500)
            )
            @Expect(registered.ok, true)
            let result = OpenClawHttpDispatcher.dispatch("POST", path, body: "{\"msg\":\"hello\"}")
            @Expect(result.ok, true)
            @Expect(result.statusCode, 200)
        }
        @Expect(runner.methods.size, 4)
        @Expect(runner.methods[0], OPENCLAW_HTTP_DISPATCH_METHOD)
        @Expect(openClawHttpJstr(runner.payloads[0], "path"), "/webhook/wechat-mp")
        @Expect(openClawHttpSidecarPublicListenerEnabled(), false)
    }

    @TestCase
    public func registryRejectsCollisionsAndDispatcherReturnsBodyTimeoutAndHandlerDiagnostics(): Unit {
        OpenClawHttpRouteRegistry.clearForTest()
        let runner = FakeOpenClawHttpRunner()
        let first = OpenClawHttpRouteRegistry.register(
            OpenClawHttpRouteRegistration("wecom", "POST", "/webhook/wecom", runner, maxBodyBytes: 4, timeoutMs: 25)
        )
        let duplicate = OpenClawHttpRouteRegistry.register(
            OpenClawHttpRouteRegistration("wecom-2", "POST", "/webhook/wecom", runner)
        )
        @Expect(first.ok, true)
        @Expect(duplicate.ok, false)
        @Expect(duplicate.diagnosticKind, "route_collision")
        @Expect(openClawHttpJstr(duplicate.diagnostic, "method"), "POST")
        @Expect(openClawHttpJstr(duplicate.diagnostic, "path"), "/webhook/wecom")

        let tooLarge = OpenClawHttpDispatcher.dispatch("POST", "/webhook/wecom", body: "12345")
        @Expect(tooLarge.ok, false)
        @Expect(tooLarge.statusCode, 413)
        @Expect(tooLarge.diagnosticKind, "body_too_large")
        @Expect(openClawHttpJstr(tooLarge.diagnostic, "method"), "POST")
        @Expect(openClawHttpJstr(tooLarge.diagnostic, "path"), "/webhook/wecom")

        let timeoutRaw = JsonObject()
        timeoutRaw.put("ok", false.toJsonValue())
        timeoutRaw.put("status", JsonString("timeout"))
        timeoutRaw.put("statusCode", 504.toJsonValue())
        let timeoutDiag = JsonObject()
        timeoutDiag.put("kind", JsonString("timeout"))
        timeoutDiag.put("message", JsonString("handler exceeded timeout"))
        timeoutDiag.put("timeoutMs", 25.toJsonValue())
        timeoutRaw.put("diagnostic", timeoutDiag)
        runner.enqueue(timeoutRaw)
        let timeout = OpenClawHttpDispatcher.dispatch("POST", "/webhook/wecom", body: "1234")
        @Expect(timeout.ok, false)
        @Expect(timeout.statusCode, 504)
        @Expect(timeout.diagnosticKind, "timeout")

        let handlerRaw = JsonObject()
        handlerRaw.put("ok", false.toJsonValue())
        handlerRaw.put("status", JsonString("error"))
        handlerRaw.put("statusCode", 500.toJsonValue())
        let handlerDiag = JsonObject()
        handlerDiag.put("kind", JsonString("handler_error"))
        handlerDiag.put("message", JsonString("boom"))
        handlerRaw.put("diagnostic", handlerDiag)
        runner.enqueue(handlerRaw)
        let handler = OpenClawHttpDispatcher.dispatch("POST", "/webhook/wecom", body: "1234")
        @Expect(handler.ok, false)
        @Expect(handler.statusCode, 500)
        @Expect(handler.diagnosticKind, "handler_error")

        let missing = OpenClawHttpDispatcher.dispatch("GET", "/webhook/wecom")
        @Expect(missing.ok, false)
        @Expect(missing.statusCode, 404)
        @Expect(missing.diagnosticKind, "route_not_found")
        @Expect(openClawHttpJstr(missing.diagnostic, "method"), "GET")
        @Expect(openClawHttpJstr(missing.diagnostic, "path"), "/webhook/wecom")
    }

    @TestCase
    public func hostCapturedWechatAndWecomWebhookRoutesAutoRegisterAndPreserveRequestShape(): Unit {
        OpenClawHttpRouteRegistry.clearForTest()
        let runner = FakeOpenClawHttpRunner()
        let routes = JsonArray([])
        for (pluginId in ["wechat-mp", "wecom", "wecom-app", "wecom-kf"]) {
            let spec = JsonObject()
            spec.put("method", JsonString("POST"))
            spec.put("path", JsonString("/webhook/${pluginId}"))
            spec.put("timeoutMs", 1800.toJsonValue())
            spec.put("maxBodyBytes", 2048.toJsonValue())
            let row = JsonObject()
            row.put("pluginId", JsonString(pluginId))
            row.put("method", JsonString("POST"))
            row.put("path", JsonString("/webhook/${pluginId}"))
            row.put("spec", spec)
            routes.add(row)
        }
        let capabilities = JsonObject()
        capabilities.put("httpRoutes", routes)
        let capture = JsonObject()
        capture.put("capabilities", capabilities)

        let registered = registerOpenClawCapturedHttpRoutes(capture, runner)

        @Expect(registered, 4)
        for (pluginId in ["wechat-mp", "wecom", "wecom-app", "wecom-kf"]) {
            runner.enqueue(openClawHttpOk(200, "{\"plugin\":\"${pluginId}\"}"))
            let query = JsonObject()
            query.put("timestamp", JsonString("123"))
            query.put("nonce", JsonString("abc"))
            let headers = JsonObject()
            headers.put("x-wechat-signature", JsonString("mock-signature"))
            headers.put("content-type", JsonString("application/json"))
            let result = OpenClawHttpDispatcher.dispatch(
                "POST",
                "/webhook/${pluginId}",
                query: query,
                headers: headers,
                body: "{\"plugin\":\"${pluginId}\",\"message\":\"mock\"}"
            )
            @Expect(result.ok, true)
            @Expect(result.body, "{\"plugin\":\"${pluginId}\"}")
            let payload = runner.payloads[runner.payloads.size - 1]
            @Expect(openClawHttpJstr(payload, "method"), "POST")
            @Expect(openClawHttpJstr(payload, "path"), "/webhook/${pluginId}")
            @Expect(openClawHttpJstr(payload.get("query").getOrThrow().asObject(), "timestamp"), "123")
            @Expect(openClawHttpJstr(payload.get("headers").getOrThrow().asObject(), "x-wechat-signature"), "mock-signature")
            @Expect(openClawHttpJstr(payload, "body"), "{\"plugin\":\"${pluginId}\",\"message\":\"mock\"}")
        }
        @Expect(openClawHttpSidecarPublicListenerEnabled(), false)
    }

    @TestCase
    public func hostGatewayRegistryEnvelopeHttpRoutesAutoRegister(): Unit {
        OpenClawHttpRouteRegistry.clearForTest()
        let runner = FakeOpenClawHttpRunner()
        let routes = JsonArray([])
        let spec = JsonObject()
        spec.put("method", JsonString("POST"))
        spec.put("path", JsonString("/webhook/weixin"))
        spec.put("timeoutMs", 2400.toJsonValue())
        let route = JsonObject()
        route.put("pluginId", JsonString("openclaw-weixin"))
        route.put("method", JsonString("POST"))
        route.put("path", JsonString("/webhook/weixin"))
        route.put("spec", spec)
        routes.add(route)
        let gatewayRegistries = JsonObject()
        gatewayRegistries.put("httpRoutes", routes)
        let capture = JsonObject()
        capture.put("gatewayRegistries", gatewayRegistries)

        let registered = registerOpenClawCapturedHttpRoutes(capture, runner)

        @Expect(registered, 1)
        runner.enqueue(openClawHttpOk(200, "{\"ok\":true}"))
        let result = OpenClawHttpDispatcher.dispatch("POST", "/webhook/weixin", body: "{\"msg\":\"hi\"}")
        @Expect(result.ok, true)
        @Expect(result.body, "{\"ok\":true}")
        @Expect(openClawHttpJstr(runner.payloads[0], "path"), "/webhook/weixin")
    }
}
