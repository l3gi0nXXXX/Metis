package metis.gateway.runtime

import metis.gateway.{
    GATEWAY_MCP_PATH,
    GATEWAY_MCP_PROTOCOL_VERSION,
    GATEWAY_MCP_SERVER_NAME,
    gatewayMcpInitializeResultJson,
    gatewayMcpPingResultJson,
    gatewayMcpToolListResultJson
}

import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject}

private func testJsonString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func testJsonObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func testJsonArray(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func testJsonBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            match (v) {
                case b: JsonBool => b.getValue()
                case _ => false
            }
        case None => false
    }
}

private func testJsonInt(obj: JsonObject, key: String): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            match (v) {
                case n: JsonInt => n.getValue()
                case _ => 0
            }
        case None => 0
    }
}

private func testToolListContains(tools: JsonArray, name: String): Bool {
    for (i in 0..tools.size()) {
        let row = try {
            tools[i].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        if (testJsonString(row, "name") == name) {
            return true
        }
    }
    false
}

@Test
public class GatewayMcpHttpSharedTest {
    @TestCase
    public func initializeResultContainsProtocolAndServerInfo(): Unit {
        let result = gatewayMcpInitializeResultJson("1.2.3")
        @Expect(testJsonString(result, "protocolVersion"), GATEWAY_MCP_PROTOCOL_VERSION)
        let serverInfo = testJsonObject(result, "serverInfo")
        @Expect(testJsonString(serverInfo, "name"), GATEWAY_MCP_SERVER_NAME)
        @Expect(testJsonString(serverInfo, "version"), "1.2.3")
        let capabilities = testJsonObject(result, "capabilities")
        let tools = testJsonObject(capabilities, "tools")
        @Expect(testJsonBool(tools, "listChanged"), false)
    }

    @TestCase
    public func pingResultContainsProvidedServerTime(): Unit {
        let result = gatewayMcpPingResultJson(42)
        @Expect(testJsonBool(result, "ok"), true)
        @Expect(testJsonInt(result, "serverTime"), 42)
    }

    @TestCase
    public func toolListContainsGatewayStatusAndOptionalConfiguredMarker(): Unit {
        let baseTools = testJsonArray(gatewayMcpToolListResultJson(), "tools")
        @Expect(testToolListContains(baseTools, "gateway.status"), true)
        @Expect(testToolListContains(baseTools, "mcp.configured"), false)

        let configuredTools = testJsonArray(
            gatewayMcpToolListResultJson(includeConfiguredMarker: true),
            "tools"
        )
        @Expect(testToolListContains(configuredTools, "mcp.configured"), true)
    }

    @TestCase
    public func mcpPathConstantMatchesGatewayRoute(): Unit {
        @Expect(GATEWAY_MCP_PATH, "/mcp")
    }
}
