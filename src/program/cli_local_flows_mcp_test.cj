package metis.program

import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

@Test
public class CliLocalFlowsMcpTest {
    @TestCase
    public func rendersMcpShowAllAsHumanTextWithoutRawJson(): Unit {
        let server = JsonObject()
        server.put("command", JsonString("uvx"))
        server.put("args", JsonArray([JsonString("context7-mcp")]))
        let root = JsonObject()
        root.put("context7", server)

        let out = cliMcpRenderServersForHuman(root)

        @Expect(out.contains("MCP servers"), true)
        @Expect(out.contains("context7"), true)
        @Expect(out.contains("command=uvx"), true)
        @Expect(out.contains("\"command\""), false)
        @Expect(out.contains("{"), false)
    }

    @TestCase
    public func rendersSingleMcpServerAsHumanTextWithoutRawJson(): Unit {
        let server = JsonObject()
        server.put("transport", JsonString("http"))
        server.put("url", JsonString("https://mcp.example.invalid"))

        let out = cliMcpRenderServerForHuman("remote", server)

        @Expect(out.contains("MCP server: remote"), true)
        @Expect(out.contains("transport=http"), true)
        @Expect(out.contains("url=https://mcp.example.invalid"), true)
        @Expect(out.contains("\"url\""), false)
        @Expect(out.contains("{"), false)
    }
}
