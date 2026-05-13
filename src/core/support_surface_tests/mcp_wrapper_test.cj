package metis.core.support_surface_tests

import metis.core.mcp.*

import magic.core.tool.*
import magic.jsonable.TypeSchema

import metis.core.{runtimeWithToolInvocationPolicyContext}

import std.collection.HashMap
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private class MCPWrapperTestTool <: Tool {
    public prop name: String {
        get() { "shellExecute" }
    }

    public prop description: String {
        get() { "test shell tool" }
    }

    public prop parameters: Array<ToolParameter> {
        get() { [] }
    }

    public prop retType: TypeSchema {
        get() { TypeSchema.Str }
    }

    public prop examples: Array<String> {
        get() { [] }
    }

    public prop extra: HashMap<String, String> {
        get() { HashMap<String, String>() }
    }

    public func invoke(_args: HashMap<String, JsonValue>): ToolResponse {
        ToolResponse("executed")
    }

    public func toJsonValue(): JsonValue {
        JsonString("shellExecute")
    }
}

@Test
public class MCPToolWrapperTest {
    @TestCase
    public func mcpWrapperRejectsDeniedToolFromRuntimePolicyContext(): Unit {
        let root = JsonObject()
        let tools = JsonObject()
        let deny = JsonArray([])
        deny.add(JsonString("exec"))
        tools.put("deny", deny)
        root.put("tools", tools)

        let wrapped = MCPToolWrapper("demo", MCPWrapperTestTool())
        let response = runtimeWithToolInvocationPolicyContext(
            root,
            ["shellExecute"],
            { => wrapped.invoke(HashMap<String, JsonValue>()) }
        )

        @Expect(response.isError, true)
        @Expect(response.content.contains("tool policy rejected"), true)
    }
}
