package metis.core.tools

import std.env.setVariable
import std.unittest.testmacro.*

@Test
public class TavilyToolTest {
    @TestCase
    public func emptyQueryFailsClosedBeforeAnyNetworkCall(): Unit {
        setVariable("TAVILY_API_KEY", "test-key")
        let tool = TavilyTool()
        @Expect(tool.search(""), "Search query cannot be empty")
    }

    @TestCase
    public func missingApiKeyReportsCanonicalMetisConfigPath(): Unit {
        setVariable("TAVILY_API_KEY", "")
        try {
            let _ = TavilyTool()
            @Assert(false)
        } catch (e: Exception) {
            @Expect(e.message.contains("tools.search.tavily.apiKey"), true)
            @Expect(e.message.contains("TAVILY_API_KEY"), true)
        }
    }
}
