package metis.gateway.openclaw_capabilities

public class OpenClawCapabilityScope {
    public let channelId: String
    public let accountId: String
    public let peerId: String
    public let threadId: String

    public init(channelId: String, accountId: String, peerId: String, threadId: String) {
        this.channelId = channelId.trimAscii()
        this.accountId = accountId.trimAscii()
        this.peerId = peerId.trimAscii()
        this.threadId = threadId.trimAscii()
    }

    public func routeKey(capabilityId: String): String {
        "${this.channelId}/${this.accountId}/${this.peerId}/${this.threadId}/${capabilityId.trimAscii()}"
    }
}

public class OpenClawCommandProjection {
    public let name: String
    public let summary: String
    public let aliases: Array<String>
    public let requiredPermissions: Array<String>

    public init(
        name: String,
        summary!: String = "",
        aliases!: Array<String> = [],
        requiredPermissions!: Array<String> = []
    ) {
        this.name = name.trimAscii()
        this.summary = summary.trimAscii()
        this.aliases = aliases
        this.requiredPermissions = requiredPermissions
    }

    public func catalogKey(): String {
        this.name
    }
}

public class OpenClawHookProjection {
    public let id: String
    public let lifecycleStages: Array<String>
    public let channelSpecific: Bool

    public init(id: String, lifecycleStages: Array<String>, channelSpecific!: Bool = false) {
        this.id = id.trimAscii()
        this.lifecycleStages = lifecycleStages
        this.channelSpecific = channelSpecific
    }

    public func canDispatch(stage: String, scope: OpenClawCapabilityScope): Bool {
        let normalized = stage.trimAscii().toAsciiLower()
        if (this.channelSpecific && scope.channelId.isEmpty()) {
            return false
        }
        this.lifecycleStages.contains(normalized)
    }
}

public class OpenClawRoutedProjection {
    public let id: String
    public let scope: OpenClawCapabilityScope

    public init(id: String, scope: OpenClawCapabilityScope) {
        this.id = id.trimAscii()
        this.scope = scope
    }

    public func routeKey(): String {
        this.scope.routeKey(this.id)
    }
}
