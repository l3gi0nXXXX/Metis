package metis.gateway.core

import std.collection.ArrayList
import std.regex.Regex
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString}

public class GatewayAgentRouteInput {
    public let root: JsonObject
    public let channel: String
    public let accountId: String
    public let defaultAccountId: String
    public let peerKind: String
    public let peerId: String
    public let parentPeerKind: String
    public let parentPeerId: String
    public let senderId: String
    public let guildId: String
    public let teamId: String
    public let roles: Array<String>
    public let dmScope: String
    public let mainDmOwnerId: String
    public let explicitAgentId: String
    public let explicitMatchedBy: String
    public let diagnostics: Array<String>

    public init(
        root: JsonObject,
        channel: String,
        accountId!: String = "",
        defaultAccountId!: String = "",
        peerKind!: String = "",
        peerId!: String = "",
        parentPeerKind!: String = "",
        parentPeerId!: String = "",
        senderId!: String = "",
        guildId!: String = "",
        teamId!: String = "",
        roles!: Array<String> = [],
        dmScope!: String = "main",
        mainDmOwnerId!: String = "",
        explicitAgentId!: String = "",
        explicitMatchedBy!: String = "",
        diagnostics!: Array<String> = []
    ) {
        this.root = root
        this.channel = gatewayRouteToken(channel)
        this.accountId = gatewayRouteNormalizeAccountId(accountId)
        this.defaultAccountId = gatewayRouteNormalizeOptionalAccountId(defaultAccountId)
        this.peerKind = gatewayRouteToken(peerKind)
        this.peerId = peerId.trimAscii()
        this.parentPeerKind = gatewayRouteToken(parentPeerKind)
        this.parentPeerId = parentPeerId.trimAscii()
        this.senderId = senderId.trimAscii()
        this.guildId = guildId.trimAscii()
        this.teamId = teamId.trimAscii()
        this.roles = gatewayRouteNormalizeArray(roles)
        this.dmScope = gatewayRouteToken(dmScope)
        this.mainDmOwnerId = mainDmOwnerId.trimAscii()
        this.explicitAgentId = explicitAgentId.trimAscii()
        this.explicitMatchedBy = explicitMatchedBy.trimAscii()
        this.diagnostics = diagnostics
    }
}

public class GatewayAgentRoute {
    public let agentId: String
    public let channel: String
    public let accountId: String
    public let preferredAccountId: String
    public let peerKind: String
    public let peerId: String
    public let sessionKey: String
    public let mainSessionKey: String
    public let lastRoutePolicy: String
    public let matchedBy: String
    public let diagnostics: Array<String>
    public let allowMainLastRouteUpdate: Bool

    public init(
        agentId: String,
        channel: String,
        accountId: String,
        preferredAccountId: String,
        peerKind: String,
        peerId: String,
        sessionKey: String,
        mainSessionKey: String,
        lastRoutePolicy: String,
        matchedBy: String,
        diagnostics: Array<String>,
        allowMainLastRouteUpdate: Bool
    ) {
        this.agentId = agentId
        this.channel = channel
        this.accountId = accountId
        this.preferredAccountId = preferredAccountId
        this.peerKind = peerKind
        this.peerId = peerId
        this.sessionKey = sessionKey
        this.mainSessionKey = mainSessionKey
        this.lastRoutePolicy = lastRoutePolicy
        this.matchedBy = matchedBy
        this.diagnostics = diagnostics
        this.allowMainLastRouteUpdate = allowMainLastRouteUpdate
    }
}

public class GatewayAgentBindingConflict {
    public let binding: JsonObject
    public let existingAgentId: String

    public init(binding: JsonObject, existingAgentId: String) {
        this.binding = binding
        this.existingAgentId = existingAgentId
    }
}

public class GatewayAgentBindingApplyResult {
    public let config: JsonObject
    public let added: Array<JsonObject>
    public let updated: Array<JsonObject>
    public let skipped: Array<JsonObject>
    public let conflicts: Array<GatewayAgentBindingConflict>

    public init(
        config: JsonObject,
        added: Array<JsonObject>,
        updated: Array<JsonObject>,
        skipped: Array<JsonObject>,
        conflicts: Array<GatewayAgentBindingConflict>
    ) {
        this.config = config
        this.added = added
        this.updated = updated
        this.skipped = skipped
        this.conflicts = conflicts
    }
}

public class GatewayAgentBindingRemoveResult {
    public let config: JsonObject
    public let removed: Array<JsonObject>
    public let missing: Array<JsonObject>
    public let conflicts: Array<GatewayAgentBindingConflict>

    public init(
        config: JsonObject,
        removed: Array<JsonObject>,
        missing: Array<JsonObject>,
        conflicts: Array<GatewayAgentBindingConflict>
    ) {
        this.config = config
        this.removed = removed
        this.missing = missing
        this.conflicts = conflicts
    }
}

private class GatewayAgentRouteCandidate {
    let binding: JsonObject
    let agentId: String
    let matchedBy: String
    let accountPattern: String
    let accountExplicit: Bool

    init(binding: JsonObject, agentId: String, matchedBy: String, accountPattern: String, accountExplicit: Bool) {
        this.binding = binding
        this.agentId = agentId
        this.matchedBy = matchedBy
        this.accountPattern = accountPattern
        this.accountExplicit = accountExplicit
    }
}

private func gatewayRouteToken(raw: String): String {
    raw.trimAscii().toAsciiLower()
}

private func gatewayRouteSanitizeAgentId(raw: String): String {
    let value = raw.trimAscii().toAsciiLower().replace("/", "_").replace("\\", "_").replace("..", "_").replace(":", "_")
    if (value.isEmpty()) {
        return "main"
    }
    value
}

private func gatewayRouteBlockedAccountKey(value: String): Bool {
    value == "__proto__" || value == "prototype" || value == "constructor"
}

private func gatewayRouteNormalizeAccountId(raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return "default"
    }
    var value = Regex("[^a-z0-9_-]+").replaceAll(trimmed.toAsciiLower(), "-")
    value = Regex("^-+").replaceAll(value, "")
    value = Regex("-+$").replaceAll(value, "")
    if (value.size > 64) {
        value = value[..64]
    }
    if (value.isEmpty() || gatewayRouteBlockedAccountKey(value)) {
        return "default"
    }
    value
}

private func gatewayRouteNormalizeOptionalAccountId(raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return ""
    }
    gatewayRouteNormalizeAccountId(trimmed)
}

private func gatewayRouteNormalizeAccountPattern(raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed == "*") {
        return "*"
    }
    gatewayRouteNormalizeAccountId(trimmed)
}

private func gatewayRouteJsonString(obj: JsonObject, key: String, fallback!: String = ""): String {
    match (obj.get(key)) {
        case Some(v) => try {
            v.asString().getValue().trimAscii()
        } catch (_e: Exception) {
            fallback
        }
        case None => fallback
    }
}

private func gatewayRouteJsonBool(obj: JsonObject, key: String, fallback!: Bool = false): Bool {
    match (obj.get(key)) {
        case Some(v) => try {
            v.asBool().getValue()
        } catch (_e: Exception) {
            fallback
        }
        case None => fallback
    }
}

private func gatewayRouteJsonObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) => try {
            v.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        case None => JsonObject()
    }
}

private func gatewayRouteJsonArray(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(v) => try {
            v.asArray()
        } catch (_e: Exception) {
            JsonArray([])
        }
        case None => JsonArray([])
    }
}

private func gatewayRouteNormalizeArray(values: Array<String>): Array<String> {
    let out = ArrayList<String>()
    for (value in values) {
        let normalized = value.trimAscii().toAsciiLower()
        if (!normalized.isEmpty()) {
            out.add(normalized)
        }
    }
    out.toArray()
}

private func gatewayRouteJsonStringArray(obj: JsonObject, key: String): Array<String> {
    let arr = gatewayRouteJsonArray(obj, key)
    let out = ArrayList<String>()
    for (item in arr.getItems()) {
        try {
            let text = item.asString().getValue().trimAscii().toAsciiLower()
            if (!text.isEmpty()) {
                out.add(text)
            }
        } catch (_e: Exception) {
            ()
        }
    }
    out.toArray()
}

private func gatewayRouteDefaultAgentId(root: JsonObject): String {
    let agents = gatewayRouteJsonObject(root, "agents")
    let list = gatewayRouteJsonArray(agents, "list")
    var first = ""
    for (i in 0..list.size()) {
        let row = try {
            list[i].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let id = gatewayRouteSanitizeAgentId(gatewayRouteJsonString(row, "id"))
        if (id.isEmpty()) {
            continue
        }
        if (first.isEmpty()) {
            first = id
        }
        if (gatewayRouteJsonBool(row, "default", fallback: false)) {
            return id
        }
    }
    if (!first.isEmpty()) {
        return first
    }
    "main"
}

private func gatewayRouteAgentExists(root: JsonObject, agentId: String): Bool {
    let agents = gatewayRouteJsonObject(root, "agents")
    let list = gatewayRouteJsonArray(agents, "list")
    if (list.size() == 0) {
        return agentId == "main"
    }
    for (i in 0..list.size()) {
        let row = try {
            list[i].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        if (gatewayRouteSanitizeAgentId(gatewayRouteJsonString(row, "id")) == agentId) {
            return true
        }
    }
    false
}

private func gatewayRouteChannelDefaultAccount(root: JsonObject, channel: String, explicitDefault: String): String {
    if (!explicitDefault.trimAscii().isEmpty()) {
        return gatewayRouteNormalizeAccountId(explicitDefault)
    }
    let channels = gatewayRouteJsonObject(root, "channels")
    let channelObj = gatewayRouteJsonObject(channels, channel)
    let configuredDefault = gatewayRouteJsonString(channelObj, "defaultAccountId")
    if (!configuredDefault.isEmpty()) {
        return gatewayRouteNormalizeAccountId(configuredDefault)
    }
    let accounts = gatewayRouteJsonArray(channelObj, "accountIds")
    if (accounts.size() > 0) {
        try {
            let first = accounts[0].asString().getValue().trimAscii()
            if (!first.isEmpty()) {
                return gatewayRouteNormalizeAccountId(first)
            }
        } catch (_e: Exception) {
            ()
        }
    }
    "default"
}

private func gatewayRouteBindingMatch(binding: JsonObject): JsonObject {
    let obj = gatewayRouteJsonObject(binding, "match")
    if (obj.size() > 0) {
        return obj
    }
    let legacy = JsonObject()
    let channel = gatewayRouteJsonString(binding, "channel")
    if (!channel.isEmpty()) {
        legacy.put("channel", JsonString(channel))
    }
    let account = gatewayRouteJsonString(binding, "accountId")
    if (!account.isEmpty()) {
        legacy.put("accountId", JsonString(account))
    }
    legacy
}

private func gatewayRouteBindingType(binding: JsonObject): String {
    let typeName = gatewayRouteJsonString(binding, "type").toAsciiLower()
    if (typeName.isEmpty()) {
        return "route"
    }
    typeName
}

private func gatewayRouteBindingEnabled(binding: JsonObject): Bool {
    gatewayRouteJsonBool(binding, "enabled", fallback: true)
}

private func gatewayRouteBindingAccountPattern(routeMatch: JsonObject, defaultAccountId: String): (String, Bool) {
    let raw = gatewayRouteJsonString(routeMatch, "accountId")
    if (raw.isEmpty()) {
        return (defaultAccountId, false)
    }
    let normalized = gatewayRouteNormalizeAccountPattern(raw)
    if (normalized == "*") {
        return ("*", true)
    }
    if (normalized == "default") {
        return (defaultAccountId, true)
    }
    (normalized, true)
}

private func gatewayRouteAccountMatches(pattern: String, accountId: String): Bool {
    pattern == "*" || pattern == accountId
}

private func gatewayRouteHasPeer(routeMatch: JsonObject): Bool {
    gatewayRouteJsonObject(routeMatch, "peer").size() > 0
}

private func gatewayRoutePeerKind(routeMatch: JsonObject): String {
    gatewayRouteToken(gatewayRouteJsonString(gatewayRouteJsonObject(routeMatch, "peer"), "kind"))
}

private func gatewayRoutePeerId(routeMatch: JsonObject): String {
    gatewayRouteJsonString(gatewayRouteJsonObject(routeMatch, "peer"), "id")
}

private func gatewayRouteRolesOverlap(bindingRoles: Array<String>, inputRoles: Array<String>): Bool {
    for (role in bindingRoles) {
        for (inputRole in inputRoles) {
            if (role == inputRole) {
                return true
            }
        }
    }
    false
}

private func gatewayRouteBasicBindingMatches(input: GatewayAgentRouteInput, binding: JsonObject, accountId: String,
    defaultAccountId: String): Bool {
    if (gatewayRouteBindingType(binding) != "route" || !gatewayRouteBindingEnabled(binding)) {
        return false
    }
    let routeMatch = gatewayRouteBindingMatch(binding)
    if (gatewayRouteToken(gatewayRouteJsonString(routeMatch, "channel")) != input.channel) {
        return false
    }
    let accountInfo = gatewayRouteBindingAccountPattern(routeMatch, defaultAccountId)
    gatewayRouteAccountMatches(accountInfo[0], accountId)
}

private func gatewayRouteFindCandidate(
    input: GatewayAgentRouteInput,
    accountId: String,
    defaultAccountId: String,
    tier: String
): Option<GatewayAgentRouteCandidate> {
    let bindings = gatewayRouteJsonArray(input.root, "bindings")
    for (i in 0..bindings.size()) {
        let binding = try {
            bindings[i].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        if (!gatewayRouteBasicBindingMatches(input, binding, accountId, defaultAccountId)) {
            continue
        }
        let routeMatch = gatewayRouteBindingMatch(binding)
        let accountInfo = gatewayRouteBindingAccountPattern(routeMatch, defaultAccountId)
        let peerKind = gatewayRoutePeerKind(routeMatch)
        let peerId = gatewayRoutePeerId(routeMatch)
        let guildId = gatewayRouteJsonString(routeMatch, "guildId")
        let teamId = gatewayRouteJsonString(routeMatch, "teamId")
        let roles = gatewayRouteJsonStringArray(routeMatch, "roles")
        match (tier) {
            case "peer.exact" =>
                if (peerKind == input.peerKind && !peerId.isEmpty() && peerId != "*" && peerId == input.peerId) {
                    return Some(
                        GatewayAgentRouteCandidate(binding,
                            gatewayRouteSanitizeAgentId(gatewayRouteJsonString(binding, "agentId")),
                            "binding.peer.exact", accountInfo[0], accountInfo[1]))
                }
            case "peer.parent" =>
                if (peerKind == input.parentPeerKind && !peerId.isEmpty() && peerId != "*" && peerId == input
                    .parentPeerId) {
                    return Some(
                        GatewayAgentRouteCandidate(binding,
                            gatewayRouteSanitizeAgentId(gatewayRouteJsonString(binding, "agentId")),
                            "binding.peer.parent", accountInfo[0], accountInfo[1]))
                }
            case "peer.wildcard" =>
                if (peerKind == input.peerKind && peerId == "*") {
                    return Some(
                        GatewayAgentRouteCandidate(binding,
                            gatewayRouteSanitizeAgentId(gatewayRouteJsonString(binding, "agentId")),
                            "binding.peer.wildcard", accountInfo[0], accountInfo[1]))
                }
            case "guild+roles" =>
                if (!guildId.isEmpty() && guildId == input.guildId && roles.size > 0 && gatewayRouteRolesOverlap(roles,
                    input.roles)) {
                    return Some(
                        GatewayAgentRouteCandidate(binding,
                            gatewayRouteSanitizeAgentId(gatewayRouteJsonString(binding, "agentId")),
                            "binding.guild+roles", accountInfo[0], accountInfo[1]))
                }
            case "guild" =>
                if (!guildId.isEmpty() && guildId == input.guildId && roles.size == 0) {
                    return Some(
                        GatewayAgentRouteCandidate(binding,
                            gatewayRouteSanitizeAgentId(gatewayRouteJsonString(binding, "agentId")), "binding.guild",
                            accountInfo[0], accountInfo[1]))
                }
            case "team" =>
                if (!teamId.isEmpty() && teamId == input.teamId && guildId.isEmpty() && !gatewayRouteHasPeer(routeMatch)) {
                    return Some(
                        GatewayAgentRouteCandidate(binding,
                            gatewayRouteSanitizeAgentId(gatewayRouteJsonString(binding, "agentId")), "binding.team",
                            accountInfo[0], accountInfo[1]))
                }
            case "account" =>
                if (!gatewayRouteHasPeer(routeMatch) && guildId.isEmpty() && teamId.isEmpty() && accountInfo[0] != "*") {
                    return Some(
                        GatewayAgentRouteCandidate(binding,
                            gatewayRouteSanitizeAgentId(gatewayRouteJsonString(binding, "agentId")), "binding.account",
                            accountInfo[0], accountInfo[1]))
                }
            case "channel" =>
                if (!gatewayRouteHasPeer(routeMatch) && guildId.isEmpty() && teamId.isEmpty() && accountInfo[0] == "*") {
                    return Some(
                        GatewayAgentRouteCandidate(binding,
                            gatewayRouteSanitizeAgentId(gatewayRouteJsonString(binding, "agentId")), "binding.channel",
                            accountInfo[0], accountInfo[1]))
                }
            case _ => ()
        }
    }
    None<GatewayAgentRouteCandidate>
}

private func gatewayRoutePickCandidate(input: GatewayAgentRouteInput, accountId: String, defaultAccountId: String): Option<GatewayAgentRouteCandidate> {
    for (tier in ["peer.exact", "peer.parent", "peer.wildcard", "guild+roles", "guild", "team", "account", "channel"]) {
        match (gatewayRouteFindCandidate(input, accountId, defaultAccountId, tier)) {
            case Some(candidate) => return Some(candidate)
            case None => ()
        }
    }
    None<GatewayAgentRouteCandidate>
}

private func gatewayRouteSessionKey(agentId: String, channel: String, accountId: String, peerKind: String,
    peerId: String, dmScope: String): String {
    if (peerKind == "direct") {
        match (dmScope) {
            case "main" => return "agent:${agentId}:main"
            case "per-peer" => return "agent:${agentId}:direct:${peerId}"
            case "per-channel-peer" => return "agent:${agentId}:${channel}:direct:${peerId}"
            case "per-account-channel-peer" => return "agent:${agentId}:${channel}:${accountId}:direct:${peerId}"
            case _ => return "agent:${agentId}:direct:${peerId}"
        }
    }
    "agent:${agentId}:${channel}:${peerKind}:${peerId}"
}

public func gatewayResolveAgentRoute(input: GatewayAgentRouteInput): GatewayAgentRoute {
    let defaultAccountId = gatewayRouteChannelDefaultAccount(input.root, input.channel, input.defaultAccountId)
    let normalizedInputAccount = gatewayRouteNormalizeAccountId(input.accountId)
    let accountId = if (normalizedInputAccount == "default") {
        defaultAccountId
    } else {
        normalizedInputAccount
    }
    let fallbackAgentId = gatewayRouteDefaultAgentId(input.root)
    let diagnostics = ArrayList<String>()
    for (diagnostic in input.diagnostics) {
        if (!diagnostic.trimAscii().isEmpty()) {
            diagnostics.add(diagnostic.trimAscii())
        }
    }

    var agentId = fallbackAgentId
    var matchedBy = "default"
    var preferredAccountId = defaultAccountId
    if (!input.explicitAgentId.isEmpty()) {
        agentId = gatewayRouteSanitizeAgentId(input.explicitAgentId)
        matchedBy = if (!input.explicitMatchedBy.isEmpty()) { input.explicitMatchedBy } else { "explicit.agentId" }
    } else {
        match (gatewayRoutePickCandidate(input, accountId, defaultAccountId)) {
            case Some(candidate) =>
                agentId = candidate.agentId
                matchedBy = candidate.matchedBy
                if (candidate.accountExplicit && candidate.accountPattern != "*") {
                    preferredAccountId = candidate.accountPattern
                }
            case None => ()
        }
    }

    if (!gatewayRouteAgentExists(input.root, agentId)) {
        diagnostics.add("unknown-agent:${agentId}")
        agentId = fallbackAgentId
    }

    let mainSessionKey = "agent:${agentId}:main"
    let sessionKey = gatewayRouteSessionKey(agentId, input.channel, accountId, input.peerKind, input.peerId,
        input.dmScope)
    let lastRoutePolicy = if (sessionKey == mainSessionKey) {
        "main"
    } else {
        "session"
    }
    var allowMainLastRouteUpdate = true
    let actor = if (!input.senderId.isEmpty()) {
        input.senderId
    } else {
        input.peerId
    }
    if (lastRoutePolicy == "main" && !input.mainDmOwnerId.isEmpty() && actor != input.mainDmOwnerId) {
        allowMainLastRouteUpdate = false
        diagnostics.add("main-dm-owner-mismatch")
    }

    GatewayAgentRoute(
        agentId,
        input.channel,
        accountId,
        preferredAccountId,
        input.peerKind,
        input.peerId,
        sessionKey,
        mainSessionKey,
        lastRoutePolicy,
        matchedBy,
        diagnostics.toArray(),
        allowMainLastRouteUpdate
    )
}

private func gatewayRoutePutString(obj: JsonObject, key: String, value: String): Unit {
    if (!value.trimAscii().isEmpty()) {
        obj.put(key, JsonString(value.trimAscii()))
    }
}

public func gatewayBuildLegacyAgentRouteBinding(agentId: String, spec: String): JsonObject {
    let parts = spec.trimAscii().split(":")
    let channel = if (parts.size > 0) {
        gatewayRouteToken(parts[0])
    } else {
        ""
    }
    let accountId = if (parts.size > 1) {
        gatewayRouteNormalizeAccountPattern(String.join(parts[1..parts.size], delimiter: ":"))
    } else {
        ""
    }
    let binding = JsonObject()
    binding.put("type", JsonString("route"))
    binding.put("agentId", JsonString(gatewayRouteSanitizeAgentId(agentId)))
    let routeMatch = JsonObject()
    gatewayRoutePutString(routeMatch, "channel", channel)
    gatewayRoutePutString(routeMatch, "accountId", accountId)
    binding.put("match", routeMatch)
    binding
}

private func gatewayRouteCopyBinding(binding: JsonObject): JsonObject {
    let out = JsonObject()
    let typeName = gatewayRouteBindingType(binding)
    out.put("type", JsonString(typeName))
    out.put("agentId", JsonString(gatewayRouteSanitizeAgentId(gatewayRouteJsonString(binding, "agentId"))))
    let sourceMatch = gatewayRouteBindingMatch(binding)
    let routeMatch = JsonObject()
    gatewayRoutePutString(routeMatch, "channel", gatewayRouteToken(gatewayRouteJsonString(sourceMatch, "channel")))
    let accountId = gatewayRouteJsonString(sourceMatch, "accountId")
    if (!accountId.isEmpty()) {
        routeMatch.put("accountId", JsonString(gatewayRouteNormalizeAccountPattern(accountId)))
    }
    let peer = gatewayRouteJsonObject(sourceMatch, "peer")
    if (peer.size() > 0) {
        let outPeer = JsonObject()
        gatewayRoutePutString(outPeer, "kind", gatewayRouteToken(gatewayRouteJsonString(peer, "kind")))
        gatewayRoutePutString(outPeer, "id", gatewayRouteJsonString(peer, "id"))
        routeMatch.put("peer", outPeer)
    }
    gatewayRoutePutString(routeMatch, "guildId", gatewayRouteJsonString(sourceMatch, "guildId"))
    gatewayRoutePutString(routeMatch, "teamId", gatewayRouteJsonString(sourceMatch, "teamId"))
    let roles = gatewayRouteJsonStringArray(sourceMatch, "roles")
    if (roles.size > 0) {
        let arr = JsonArray([])
        for (role in roles) {
            arr.add(JsonString(role))
        }
        routeMatch.put("roles", arr)
    }
    out.put("match", routeMatch)
    match (binding.get("enabled")) {
        case Some(v) => out.put("enabled", v)
        case None => ()
    }
    match (binding.get("comment")) {
        case Some(v) => out.put("comment", v)
        case None => ()
    }
    out
}

private func gatewayRouteApplyIdentityKey(binding: JsonObject): String {
    let routeMatch = gatewayRouteBindingMatch(binding)
    let peer = gatewayRouteJsonObject(routeMatch, "peer")
    let roles = gatewayRouteJsonStringArray(routeMatch, "roles")
    var rolePart = ""
    for (role in roles) {
        if (!rolePart.isEmpty()) {
            rolePart += ","
        }
        rolePart += role
    }
    gatewayRouteJoinKey(
        [
            gatewayRouteToken(gatewayRouteJsonString(routeMatch, "channel")),
            gatewayRouteToken(gatewayRouteJsonString(peer, "kind")),
            gatewayRouteJsonString(peer, "id"),
            gatewayRouteJsonString(routeMatch, "guildId"),
            gatewayRouteJsonString(routeMatch, "teamId"),
            rolePart
        ]
    )
}

private func gatewayRouteJoinKey(parts: Array<String>): String {
    var out = ""
    for (part in parts) {
        if (!out.isEmpty()) {
            out += "|"
        }
        out += part
    }
    out
}

private func gatewayRouteApplyAccountKey(binding: JsonObject): String {
    let account = gatewayRouteNormalizeAccountPattern(gatewayRouteJsonString(gatewayRouteBindingMatch(binding), "accountId"))
    if (account == "default") {
        return "default"
    }
    account
}

private func gatewayRouteApplyKey(binding: JsonObject): String {
    "${gatewayRouteApplyIdentityKey(binding)}|${gatewayRouteApplyAccountKey(binding)}"
}

private func gatewayRouteApplyFindExistingByKey(bindings: ArrayList<JsonObject>, key: String): Option<Int64> {
    for (i in 0..bindings.size) {
        if (gatewayRouteApplyKey(bindings[i]) == key) {
            return Some(i)
        }
    }
    None<Int64>
}

private func gatewayRouteApplyFindScopeUpgrade(bindings: ArrayList<JsonObject>, incoming: JsonObject): Option<Int64> {
    let incomingIdentity = gatewayRouteApplyIdentityKey(incoming)
    let incomingAccount = gatewayRouteNormalizeAccountPattern(gatewayRouteJsonString(gatewayRouteBindingMatch(incoming), "accountId"))
    let incomingAgent = gatewayRouteSanitizeAgentId(gatewayRouteJsonString(incoming, "agentId"))
    if (incomingAccount == "default" || incomingAccount == "*") {
        return None<Int64>
    }
    for (i in 0..bindings.size) {
        let existing = bindings[i]
        if (!gatewayRouteBindingEnabled(existing)) {
            continue
        }
        if (gatewayRouteApplyIdentityKey(existing) != incomingIdentity) {
            continue
        }
        if (gatewayRouteNormalizeAccountPattern(gatewayRouteJsonString(gatewayRouteBindingMatch(existing), "accountId")) != "default") {
            continue
        }
        if (gatewayRouteSanitizeAgentId(gatewayRouteJsonString(existing, "agentId")) == incomingAgent) {
            return Some(i)
        }
    }
    None<Int64>
}

private func gatewayRouteApplyScopeUpgradeBinding(existing: JsonObject, incoming: JsonObject): JsonObject {
    let out = gatewayRouteCopyBinding(incoming)
    match (existing.get("enabled")) {
        case Some(v) => out.put("enabled", v)
        case None => ()
    }
    match (existing.get("comment")) {
        case Some(v) => out.put("comment", v)
        case None => ()
    }
    out
}

public func gatewayApplyAgentRouteBindings(root: JsonObject, bindings: JsonArray): GatewayAgentBindingApplyResult {
    let preservedBindings = ArrayList<JsonObject>()
    let existingBindings = ArrayList<JsonObject>()
    let source = gatewayRouteJsonArray(root, "bindings")
    for (i in 0..source.size()) {
        let row = try {
            source[i].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        if (gatewayRouteBindingType(row) == "route") {
            existingBindings.add(gatewayRouteCopyBinding(row))
        } else {
            preservedBindings.add(row)
        }
    }

    let added = ArrayList<JsonObject>()
    let updated = ArrayList<JsonObject>()
    let skipped = ArrayList<JsonObject>()
    let conflicts = ArrayList<GatewayAgentBindingConflict>()

    for (i in 0..bindings.size()) {
        let incomingRaw = try {
            bindings[i].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        if (gatewayRouteBindingType(incomingRaw) != "route" || !gatewayRouteBindingEnabled(incomingRaw)) {
            skipped.add(incomingRaw)
            continue
        }
        let incoming = gatewayRouteCopyBinding(incomingRaw)
        let incomingAgent = gatewayRouteSanitizeAgentId(gatewayRouteJsonString(incoming, "agentId"))
        let key = gatewayRouteApplyKey(incoming)
        match (gatewayRouteApplyFindExistingByKey(existingBindings, key)) {
            case Some(idx) =>
                let existing = existingBindings[idx]
                let existingAgent = gatewayRouteSanitizeAgentId(gatewayRouteJsonString(existing, "agentId"))
                if (existingAgent == incomingAgent) {
                    skipped.add(incoming)
                } else {
                    conflicts.add(GatewayAgentBindingConflict(incoming, existingAgent))
                }
                continue
            case None => ()
        }
        match (gatewayRouteApplyFindScopeUpgrade(existingBindings, incoming)) {
            case Some(idx) =>
                let updatedBinding = gatewayRouteApplyScopeUpgradeBinding(existingBindings[idx], incoming)
                existingBindings[idx] = updatedBinding
                updated.add(updatedBinding)
                continue
            case None => ()
        }
        existingBindings.add(incoming)
        added.add(incoming)
    }

    let outBindings = JsonArray([])
    for (binding in preservedBindings) {
        outBindings.add(binding)
    }
    for (binding in existingBindings) {
        outBindings.add(binding)
    }
    root.put("bindings", outBindings)
    GatewayAgentBindingApplyResult(root, added.toArray(), updated.toArray(), skipped.toArray(), conflicts.toArray())
}

public func gatewayRemoveAgentRouteBindings(root: JsonObject, bindings: JsonArray): GatewayAgentBindingRemoveResult {
    let preservedBindings = ArrayList<JsonObject>()
    let existingBindings = ArrayList<JsonObject>()
    let source = gatewayRouteJsonArray(root, "bindings")
    for (i in 0..source.size()) {
        let row = try {
            source[i].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        if (gatewayRouteBindingType(row) == "route") {
            existingBindings.add(gatewayRouteCopyBinding(row))
        } else {
            preservedBindings.add(row)
        }
    }

    let removedIndexes = ArrayList<Int64>()
    let removed = ArrayList<JsonObject>()
    let missing = ArrayList<JsonObject>()
    let conflicts = ArrayList<GatewayAgentBindingConflict>()

    for (i in 0..bindings.size()) {
        let incomingRaw = try {
            bindings[i].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        if (gatewayRouteBindingType(incomingRaw) != "route") {
            missing.add(incomingRaw)
            continue
        }
        let incoming = gatewayRouteCopyBinding(incomingRaw)
        let desiredAgent = gatewayRouteSanitizeAgentId(gatewayRouteJsonString(incoming, "agentId"))
        let key = gatewayRouteApplyKey(incoming)
        var matchedIndex: Int64 = -1
        var conflictingAgent = ""
        for (j in 0..existingBindings.size) {
            if (removedIndexes.contains(j)) {
                continue
            }
            let current = existingBindings[j]
            if (gatewayRouteApplyKey(current) != key) {
                continue
            }
            let currentAgent = gatewayRouteSanitizeAgentId(gatewayRouteJsonString(current, "agentId"))
            if (currentAgent == desiredAgent) {
                matchedIndex = j
                break
            }
            conflictingAgent = currentAgent
        }
        if (matchedIndex >= 0) {
            removedIndexes.add(matchedIndex)
            removed.add(existingBindings[matchedIndex])
        } else if (!conflictingAgent.isEmpty()) {
            conflicts.add(GatewayAgentBindingConflict(incoming, conflictingAgent))
        } else {
            missing.add(incoming)
        }
    }

    let outBindings = JsonArray([])
    for (binding in preservedBindings) {
        outBindings.add(binding)
    }
    for (i in 0..existingBindings.size) {
        if (!removedIndexes.contains(i)) {
            outBindings.add(existingBindings[i])
        }
    }
    root.put("bindings", outBindings)
    GatewayAgentBindingRemoveResult(root, removed.toArray(), missing.toArray(), conflicts.toArray())
}
