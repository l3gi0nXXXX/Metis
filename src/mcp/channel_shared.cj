package metis.mcp

public let MCP_CLAUDE_CHANNEL_MODE_AUTO = "auto"
public let MCP_CLAUDE_CHANNEL_MODE_ON = "on"
public let MCP_CLAUDE_CHANNEL_MODE_OFF = "off"

public func normalizeMcpClaudeChannelMode(raw: String): String {
    let normalized = raw.trimAscii().toAsciiLower()
    if (normalized == MCP_CLAUDE_CHANNEL_MODE_ON) {
        return MCP_CLAUDE_CHANNEL_MODE_ON
    }
    if (normalized == MCP_CLAUDE_CHANNEL_MODE_OFF) {
        return MCP_CLAUDE_CHANNEL_MODE_OFF
    }
    MCP_CLAUDE_CHANNEL_MODE_AUTO
}

public func isValidMcpClaudeChannelMode(raw: String): Bool {
    let normalized = raw.trimAscii().toAsciiLower()
    normalized == MCP_CLAUDE_CHANNEL_MODE_AUTO ||
        normalized == MCP_CLAUDE_CHANNEL_MODE_ON ||
        normalized == MCP_CLAUDE_CHANNEL_MODE_OFF
}

public class MetisMcpServeOptions {
    public let gatewayUrl: String
    public let gatewayToken: String
    public let gatewayPassword: String
    public let claudeChannelMode: String
    public let verbose: Bool

    public init(
        gatewayUrl!: String = "",
        gatewayToken!: String = "",
        gatewayPassword!: String = "",
        claudeChannelMode!: String = MCP_CLAUDE_CHANNEL_MODE_AUTO,
        verbose!: Bool = false
    ) {
        this.gatewayUrl = gatewayUrl.trimAscii()
        this.gatewayToken = gatewayToken.trimAscii()
        this.gatewayPassword = gatewayPassword.trimAscii()
        this.claudeChannelMode = normalizeMcpClaudeChannelMode(claudeChannelMode)
        this.verbose = verbose
    }
}
