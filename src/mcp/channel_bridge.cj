package metis.mcp

import metis.core.mcp.serveMetisMcpStdio

/**
 * Phase 1 MCP bridge shell.
 *
 * For now this preserves the existing stdio -> gateway /mcp forwarding
 * behavior while we move the public entrypoint onto the future gateway-style
 * module layout. Later phases will replace the internals with a stateful
 * conversation bridge.
 */
public class MetisChannelBridge {
    private let options: MetisMcpServeOptions

    public init(options: MetisMcpServeOptions) {
        this.options = options
    }

    public func effectiveClaudeChannelMode(): String {
        this.options.claudeChannelMode
    }

    public func serve(): Int64 {
        serveMetisMcpStdio(
            gatewayUrl: this.options.gatewayUrl,
            gatewayToken: this.options.gatewayToken,
            gatewayPassword: this.options.gatewayPassword,
            claudeChannelMode: this.options.claudeChannelMode,
            verbose: this.options.verbose
        )
    }
}
