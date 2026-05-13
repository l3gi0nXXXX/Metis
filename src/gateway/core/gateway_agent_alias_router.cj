package metis.gateway.core

import std.collection.ArrayList
import std.regex.{Regex, RegexFlag}
import stdx.encoding.json.{JsonArray, JsonObject}

private let GATEWAY_AGENT_ALIAS_MAX_PATTERN_LENGTH: Int64 = 128
private let GATEWAY_AGENT_ALIAS_MAX_TEXT_LENGTH: Int64 = 4096

public class GatewayAgentAliasRouteDecision {
    public let agentId: String
    public let matchedBy: String
    public let pattern: String
    public let diagnostics: Array<String>

    public init(
        agentId!: String = "",
        matchedBy!: String = "",
        pattern!: String = "",
        diagnostics!: Array<String> = []
    ) {
        this.agentId = gatewayAgentAliasSanitizeAgentId(agentId)
        this.matchedBy = matchedBy.trimAscii()
        this.pattern = pattern.trimAscii()
        this.diagnostics = diagnostics
    }
}

private func gatewayAgentAliasSanitizeAgentId(raw: String): String {
    raw.trimAscii().toAsciiLower().replace("/", "_").replace("\\", "_").replace("..", "_").replace(":", "_")
}

private func gatewayAgentAliasJsonString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func gatewayAgentAliasJsonObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func gatewayAgentAliasJsonArray(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func gatewayAgentAliasClipText(raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed.size <= GATEWAY_AGENT_ALIAS_MAX_TEXT_LENGTH) {
        return trimmed
    }
    trimmed[..GATEWAY_AGENT_ALIAS_MAX_TEXT_LENGTH]
}

private func gatewayAgentAliasTexts(searchTexts: Array<String>): Array<String> {
    let out = ArrayList<String>()
    for (text in searchTexts) {
        let clipped = gatewayAgentAliasClipText(text)
        if (!clipped.isEmpty()) {
            out.add(clipped)
        }
    }
    out.toArray()
}

private func gatewayAgentAliasRegexMatches(pattern: String, text: String): Bool {
    try {
        let regex = Regex(pattern, [RegexFlag.MultiLine, RegexFlag.IgnoreCase])
        for (_match in regex.findAll(text)) {
            return true
        }
        false
    } catch (_e: Exception) {
        false
    }
}

private func gatewayAgentAliasLooksRegexLike(pattern: String): Bool {
    for (r in pattern.runes()) {
        if (r == r'(' || r == r')' || r == r'[' || r == r']' || r == r'{' || r == r'}' ||
            r == r'*' || r == r'+' || r == r'?' || r == r'|' || r == r'^' || r == r'$' ||
            r == r'\\' || r == r'.') {
            return true
        }
    }
    false
}

private func gatewayAgentAliasPatternMatches(pattern: String, searchTexts: Array<String>): Bool {
    let normalizedPattern = pattern.toAsciiLower()
    let regexLike = gatewayAgentAliasLooksRegexLike(pattern)
    for (text in searchTexts) {
        if (!regexLike && text.toAsciiLower().contains(normalizedPattern)) {
            return true
        }
        if (gatewayAgentAliasRegexMatches(pattern, text)) {
            return true
        }
    }
    false
}

private func gatewayAgentAliasPatternHasInvalidRegex(pattern: String): Bool {
    try {
        Regex(pattern, [RegexFlag.MultiLine, RegexFlag.IgnoreCase])
        false
    } catch (_e: Exception) {
        true
    }
}

public func gatewayResolveAgentAliasRoute(root: JsonObject, searchTexts: Array<String>): GatewayAgentAliasRouteDecision {
    let diagnostics = ArrayList<String>()
    let texts = gatewayAgentAliasTexts(searchTexts)
    if (texts.isEmpty()) {
        return GatewayAgentAliasRouteDecision(diagnostics: diagnostics.toArray())
    }

    let agents = gatewayAgentAliasJsonObject(root, "agents")
    let list = gatewayAgentAliasJsonArray(agents, "list")
    for (i in 0..list.size()) {
        let agent = try { list[i].asObject() } catch (_e: Exception) { JsonObject() }
        let agentId = gatewayAgentAliasSanitizeAgentId(gatewayAgentAliasJsonString(agent, "id"))
        if (agentId.isEmpty()) {
            continue
        }
        let groupChat = gatewayAgentAliasJsonObject(agent, "groupChat")
        let patterns = gatewayAgentAliasJsonArray(groupChat, "mentionPatterns")
        for (j in 0..patterns.size()) {
            let pattern = try { patterns[j].asString().getValue().trimAscii() } catch (_e: Exception) { "" }
            if (pattern.isEmpty()) {
                continue
            }
            if (pattern.size > GATEWAY_AGENT_ALIAS_MAX_PATTERN_LENGTH) {
                diagnostics.add("alias-pattern-too-long:${agentId}")
                continue
            }
            if (gatewayAgentAliasPatternMatches(pattern, texts)) {
                return GatewayAgentAliasRouteDecision(
                    agentId: agentId,
                    matchedBy: "alias.mention",
                    pattern: pattern,
                    diagnostics: diagnostics.toArray()
                )
            }
            if (gatewayAgentAliasPatternHasInvalidRegex(pattern)) {
                diagnostics.add("alias-pattern-invalid-regex:${agentId}")
            }
        }
    }
    GatewayAgentAliasRouteDecision(diagnostics: diagnostics.toArray())
}
