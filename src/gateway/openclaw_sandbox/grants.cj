package metis.gateway.openclaw_sandbox

import std.collection.ArrayList

public class OpenClawSandboxGrantSet {
    public let grants: Array<String>

    public init(grants: Array<String>) {
        let normalized = ArrayList<String>()
        for (grant in grants) {
            let value = grant.trimAscii().toAsciiLower()
            if (!value.isEmpty() && !normalized.contains(value)) {
                normalized.add(value)
            }
        }
        this.grants = normalized.toArray()
    }

    public func has(grant: String): Bool {
        this.grants.contains(grant.trimAscii().toAsciiLower())
    }

    public func missing(required: Array<String>): Array<String> {
        let out = ArrayList<String>()
        for (grant in required) {
            let normalized = grant.trimAscii().toAsciiLower()
            if (!normalized.isEmpty() && !this.has(normalized) && !out.contains(normalized)) {
                out.add(normalized)
            }
        }
        out.toArray()
    }

    public func allowsAll(required: Array<String>): Bool {
        this.missing(required).isEmpty()
    }

    public func canSpawnProcess(): Bool {
        this.has("process:spawn")
    }

    public func canUseBrowser(): Bool {
        this.has("browser:automation") || this.has("browser:not-applicable")
    }

    public func canUseRealtime(): Bool {
        this.has("realtime:stream")
    }
}
