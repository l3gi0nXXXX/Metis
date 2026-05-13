package metis.core.support_surface_tests

import metis.mcp.*

import std.unittest.testmacro.*

@Test
public class MetisMcpChannelSharedTest {
    @TestCase
    public func normalizeClaudeChannelMode(): Unit {
        @Expect(normalizeMcpClaudeChannelMode("auto"), "auto")
        @Expect(normalizeMcpClaudeChannelMode(" ON "), "on")
        @Expect(normalizeMcpClaudeChannelMode("off"), "off")
        @Expect(normalizeMcpClaudeChannelMode("invalid"), "auto")
    }

    @TestCase
    public func validateClaudeChannelMode(): Unit {
        @Expect(isValidMcpClaudeChannelMode("auto"), true)
        @Expect(isValidMcpClaudeChannelMode("on"), true)
        @Expect(isValidMcpClaudeChannelMode("off"), true)
        @Expect(isValidMcpClaudeChannelMode("AUTO"), true)
        @Expect(isValidMcpClaudeChannelMode("bad"), false)
    }

    @TestCase
    public func serverOptionsNormalizeValues(): Unit {
        let options = MetisMcpServeOptions(
            gatewayUrl: "  ws://127.0.0.1:18788/ws  ",
            gatewayToken: "  token  ",
            gatewayPassword: "  password  ",
            claudeChannelMode: " ON ",
            verbose: true
        )
        @Expect(options.gatewayUrl, "ws://127.0.0.1:18788/ws")
        @Expect(options.gatewayToken, "token")
        @Expect(options.gatewayPassword, "password")
        @Expect(options.claudeChannelMode, "on")
        @Expect(options.verbose, true)
    }

    @TestCase
    public func channelServerExposesNormalizedMode(): Unit {
        let server = createMetisChannelMcpServer(
            options: MetisMcpServeOptions(claudeChannelMode: "OFF")
        )
        @Expect(server.effectiveClaudeChannelMode(), "off")
    }
}
