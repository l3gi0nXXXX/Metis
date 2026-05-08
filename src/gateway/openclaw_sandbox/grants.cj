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
        this.has("realtime:stream") || this.has("realtime:not-applicable")
    }
}

public class OpenClawSandboxRuntimeResult {
    public let contract: String = "metis.openclaw-sandbox.v1"
    public let ok: Bool
    public let status: String
    public let facet: String
    public let action: String
    public let notApplicable: Bool
    public let reason: String

    public init(ok: Bool, status: String, facet: String, action: String, notApplicable!: Bool = false, reason!: String = "") {
        this.ok = ok
        this.status = status.trimAscii()
        this.facet = facet.trimAscii()
        this.action = action.trimAscii()
        this.notApplicable = notApplicable
        this.reason = reason.trimAscii()
    }
}

public class OpenClawSandboxManager {
    public let grants: OpenClawSandboxGrantSet

    public init(grants: OpenClawSandboxGrantSet) {
        this.grants = grants
    }

    public func spawnProcess(command: String, args: Array<String>): OpenClawSandboxRuntimeResult {
        let _ = args
        if (!this.grants.canSpawnProcess()) {
            return OpenClawSandboxRuntimeResult(false, "permission_denied", "process", "spawn", reason: "process:spawn grant is required")
        }
        if (command.trimAscii().isEmpty()) {
            return OpenClawSandboxRuntimeResult(false, "invalid_request", "process", "spawn", reason: "command is required")
        }
        OpenClawSandboxRuntimeResult(true, "authorized", "process", "spawn")
    }

    public func browserAutomation(action: String): OpenClawSandboxRuntimeResult {
        if (this.grants.has("browser:not-applicable")) {
            return OpenClawSandboxRuntimeResult(
                false,
                "not_applicable",
                "browser",
                action,
                notApplicable: true,
                reason: "browser automation is intentionally not exposed by this Metis runtime slice"
            )
        }
        if (!this.grants.canUseBrowser()) {
            return OpenClawSandboxRuntimeResult(false, "permission_denied", "browser", action, reason: "browser grant is required")
        }
        OpenClawSandboxRuntimeResult(true, "authorized", "browser", action)
    }

    public func realtimeSession(action: String): OpenClawSandboxRuntimeResult {
        if (this.grants.has("realtime:not-applicable")) {
            return OpenClawSandboxRuntimeResult(
                false,
                "not_applicable",
                "realtime",
                action,
                notApplicable: true,
                reason: "realtime socket/session runtime is intentionally not exposed by this Metis runtime slice"
            )
        }
        if (!this.grants.canUseRealtime()) {
            return OpenClawSandboxRuntimeResult(false, "permission_denied", "realtime", action, reason: "realtime grant is required")
        }
        OpenClawSandboxRuntimeResult(true, "authorized", "realtime", action)
    }

    public func notApplicableEvidence(): Array<String> {
        let out = ArrayList<String>()
        for (grant in this.grants.grants) {
            if (grant.contains(":not-applicable")) {
                out.add(grant)
            }
        }
        out.toArray()
    }
}
