package metis.mcp

public class MetisChannelMcpServer {
    private let bridge: MetisChannelBridge

    public init(options: MetisMcpServeOptions) {
        this.bridge = MetisChannelBridge(options)
    }

    public func effectiveClaudeChannelMode(): String {
        this.bridge.effectiveClaudeChannelMode()
    }

    public func serve(): Int64 {
        this.bridge.serve()
    }
}

public func createMetisChannelMcpServer(
    options!: MetisMcpServeOptions = MetisMcpServeOptions()
): MetisChannelMcpServer {
    MetisChannelMcpServer(options)
}

public func serveMetisChannelMcp(
    options!: MetisMcpServeOptions = MetisMcpServeOptions()
): Int64 {
    createMetisChannelMcpServer(options: options).serve()
}
