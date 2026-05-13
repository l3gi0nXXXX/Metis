package metis.gateway.tools

import std.collection.ArrayList
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString, JsonValue}

@Test
public class GatewayFeishuOapiToolsetTest {
    @TestCase
    public func defaultClientReturnsStructuredAuthRequiredPlaceholder(): Unit {
        let out = GatewayFeishuOapiToolset().debugFeishuOapiInvokeForTest(
            "feishu_fetch_doc",
            "fetch",
            Some("default"),
            Some("{\"doc_id\":\"doccn_demo\"}")
        )
        let json = JsonValue.fromStr(out).asObject()
        @Expect(json.get("ok").getOrThrow().asBool().getValue(), false)
        @Expect(json.get("status").getOrThrow().asString().getValue(), "auth_required")
        @Expect(json.get("tool").getOrThrow().asString().getValue(), "feishu_fetch_doc")
        @Expect(json.get("category").getOrThrow().asString().getValue(), "docs")
        @Expect(json.get("action").getOrThrow().asString().getValue(), "fetch")
        @Expect(json.get("account_id").getOrThrow().asString().getValue(), "default")
        let auth = json.get("auth").getOrThrow().asObject()
        @Expect(auth.get("required").getOrThrow().asBool().getValue(), true)
        @Expect(auth.get("state").getOrThrow().asString().getValue(), "absent")
        @Expect(json.get("required_scopes").getOrThrow().asArray()[0].asString().getValue(), "docx:document:readonly")
    }

    @TestCase
    public func fakeClientReceivesStructuredRequestAndCanReportScopeMissing(): Unit {
        let captured = ArrayList<String>()
        debugSetGatewayFeishuOapiToolCallRunnerForTest(Some({ method: String, payload: JsonObject =>
            captured.add(method)
            captured.add(payload.get("tool").getOrThrow().asString().getValue())
            captured.add(payload.get("category").getOrThrow().asString().getValue())
            captured.add(payload.get("action").getOrThrow().asString().getValue())
            captured.add(payload.get("account_id").getOrThrow().asString().getValue())
            captured.add(payload.get("params").getOrThrow().asObject().get("summary").getOrThrow().asString().getValue())

            let out = JsonObject()
            out.put("ok", JsonBool(false))
            out.put("status", JsonString("scope_missing"))
            out.put("missing_scopes", JsonArray([JsonString("calendar:calendar:readonly")]))
            out
        }))
        try {
            let out = GatewayFeishuOapiToolset().debugFeishuOapiInvokeForTest(
                "feishu_calendar_event",
                "list",
                Some("work"),
                Some("{\"summary\":\"standup\"}")
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("ok").getOrThrow().asBool().getValue(), false)
            @Expect(json.get("status").getOrThrow().asString().getValue(), "scope_missing")
            @Expect(json.get("tool").getOrThrow().asString().getValue(), "feishu_calendar_event")
            @Expect(json.get("category").getOrThrow().asString().getValue(), "calendar")
            @Expect(json.get("missing_scopes").getOrThrow().asArray()[0].asString().getValue(), "calendar:calendar:readonly")
            @Expect(captured[0], "feishu_calendar_event")
            @Expect(captured[1], "feishu_calendar_event")
            @Expect(captured[2], "calendar")
            @Expect(captured[3], "list")
            @Expect(captured[4], "work")
            @Expect(captured[5], "standup")
        } finally {
            debugSetGatewayFeishuOapiToolCallRunnerForTest(None<(String, JsonObject) -> JsonObject>)
        }
    }

    @TestCase
    public func invalidParamsJsonReturnsStructuredInvalidRequest(): Unit {
        let out = GatewayFeishuOapiToolset().debugFeishuOapiInvokeForTest(
            "feishu_bitable_app",
            "list",
            None<String>,
            Some("not-json")
        )
        let json = JsonValue.fromStr(out).asObject()
        @Expect(json.get("ok").getOrThrow().asBool().getValue(), false)
        @Expect(json.get("status").getOrThrow().asString().getValue(), "invalid_request")
        @Expect(json.get("tool").getOrThrow().asString().getValue(), "feishu_bitable_app")
    }
}
