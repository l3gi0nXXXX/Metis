package metis.gateway.openclaw_security

import magic.jsonable.*
import std.collection.ArrayList
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

public class OpenClawPermissionRequirement {
    public let category: String
    public let action: String
    public let resource: String
    public let source: String
    public let reason: String

    public init(category: String, action: String, resource: String, source: String, reason: String) {
        this.category = category.trimAscii().toAsciiLower()
        this.action = action.trimAscii().toAsciiLower()
        this.resource = openClawNormalizeResource(this.category, resource)
        this.source = source.trimAscii()
        this.reason = reason.trimAscii()
    }
}

private class OpenClawSourceRule {
    public let url: String
    public let ref: String
    public let hash: String

    public init(url: String, ref: String, hash: String) {
        this.url = url.trimAscii()
        this.ref = ref.trimAscii()
        this.hash = hash.trimAscii()
    }
}

public class OpenClawSecurityPolicy {
    private let pluginId: String
    private let grants = ArrayList<OpenClawPermissionRequirement>()
    private let sources = ArrayList<OpenClawSourceRule>()

    public init(pluginId: String) {
        this.pluginId = pluginId.trimAscii()
    }

    public func grant(category: String, action: String, resource: String): Unit {
        this.grants.add(OpenClawPermissionRequirement(category, action, resource, "grant", "configured grant"))
    }

    public func allowSource(url: String, ref!: String = "", hash!: String = ""): Unit {
        this.sources.add(OpenClawSourceRule(url, ref, hash))
    }

    public func enforceInstallSource(url: String, ref: String, hash: String): JsonObject {
        let trimmedUrl = url.trimAscii()
        for (rule in this.sources) {
            if (rule.url != trimmedUrl) {
                continue
            }
            if (!rule.ref.isEmpty() && rule.ref != ref.trimAscii()) {
                return openClawDecision(this.pluginId, "install", false, "source_ref_mismatch")
            }
            if (!rule.hash.isEmpty() && rule.hash != hash.trimAscii()) {
                return openClawDecision(this.pluginId, "install", false, "source_hash_mismatch")
            }
            return openClawDecision(this.pluginId, "install", true, "allowed")
        }
        openClawDecision(this.pluginId, "install", false, "source_not_allowed")
    }

    public func enforceStart(requirements: ArrayList<OpenClawPermissionRequirement>): JsonObject {
        let denied = JsonArray([])
        for (requirement in requirements) {
            if (!this.hasGrant(requirement)) {
                denied.add(openClawRequirementJson(requirement))
            }
        }
        let decision = openClawDecision(this.pluginId, "start", denied.size() == 0, if (denied.size() == 0) { "allowed" } else { "permission_denied" })
        decision.put("denied", denied)
        return decision
    }

    public func enforceHandlerDispatch(requirements: ArrayList<OpenClawPermissionRequirement>): JsonObject {
        let denied = JsonArray([])
        for (requirement in requirements) {
            if (!this.hasGrant(requirement)) {
                denied.add(openClawRequirementJson(requirement))
            }
        }
        let decision = openClawDecision(this.pluginId, "handler-dispatch", denied.size() == 0, if (denied.size() == 0) { "allowed" } else { "permission_denied" })
        decision.put("denied", denied)
        return decision
    }

    public func enforceRuntimePermission(requirement: OpenClawPermissionRequirement): JsonObject {
        let ok = this.hasGrant(requirement)
        let decision = openClawDecision(this.pluginId, "handler", ok, if (ok) { "allowed" } else { "permission_denied" })
        if (!ok) {
            decision.put("denied", JsonArray([openClawRequirementJson(requirement)]))
        }
        return decision
    }

    private func hasGrant(requirement: OpenClawPermissionRequirement): Bool {
        for (grant in this.grants) {
            if (grant.category != requirement.category) {
                continue
            }
            if (grant.action != requirement.action && grant.action != "*" && !(grant.category == "network" && grant.action == "use")) {
                continue
            }
            if (grant.resource == "*" || grant.resource == requirement.resource) {
                return true
            }
        }
        false
    }
}

public func openClawHandlerCrashDecision(pluginId: String, stage: String, message: String): JsonObject {
    let decision = openClawDecision(pluginId, stage, false, "handler_crash")
    let diagnostics = JsonObject()
    diagnostics.put("message", JsonString(openClawRedactString(message)))
    decision.put("diagnostics", diagnostics)
    decision
}

public func openClawHandlerTimeoutDecision(pluginId: String, stage: String, timeoutMs: Int64): JsonObject {
    let decision = openClawDecision(pluginId, stage, false, "handler_timeout")
    let diagnostics = JsonObject()
    diagnostics.put("timeoutMs", timeoutMs.toJsonValue())
    decision.put("diagnostics", diagnostics)
    decision
}

private func openClawDecision(pluginId: String, stage: String, allowed: Bool, code: String): JsonObject {
    let out = JsonObject()
    out.put("pluginId", JsonString(pluginId.trimAscii()))
    out.put("stage", JsonString(stage.trimAscii()))
    out.put("allowed", allowed.toJsonValue())
    out.put("code", JsonString(code.trimAscii()))
    out.put("diagnostics", JsonObject())
    return out
}

private func openClawRequirementJson(requirement: OpenClawPermissionRequirement): JsonObject {
    let out = JsonObject()
    out.put("category", JsonString(requirement.category))
    out.put("action", JsonString(requirement.action))
    out.put("resource", JsonString(if (requirement.category == "secret" || openClawIsSensitive(requirement.resource)) { "[REDACTED]" } else { requirement.resource }))
    out.put("source", JsonString(openClawRedactString(requirement.source)))
    out.put("reason", JsonString(openClawRedactString(requirement.reason)))
    return out
}

private func openClawNormalizeResource(category: String, resource: String): String {
    let trimmed = resource.trimAscii()
    if (category == "network" || category == "webhook") {
        var text = trimmed
        if (text.startsWith("https://")) {
            text = text[8..text.size]
        } else if (text.startsWith("http://")) {
            text = text[7..text.size]
        }
        let slash = text.indexOf("/")
        match (slash) {
            case Some(i) => text[0..i]
            case None => text
        }
    } else {
        trimmed
    }
}

private func openClawIsSensitive(value: String): Bool {
    let lower = value.toAsciiLower()
    lower.contains("token") || lower.contains("secret") || lower.contains("password") ||
        lower.contains("authorization") || lower.contains("credential") || lower.contains("api_key")
}

private func openClawRedactString(value: String): String {
    let lower = value.toAsciiLower()
    if (lower.contains("bearer ") || lower.contains("password=") || lower.contains("token=") || lower.contains("secret=")) {
        return "[REDACTED]"
    }
    value
}
