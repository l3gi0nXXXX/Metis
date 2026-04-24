package metis.core.memory

import metis.core.config.CliConfig

public class QmdScopeInfo {
    public let channel: Option<String>
    public let chatType: Option<String>
    public let normalizedKey: Option<String>
    public let rawKey: String

    public init(
        channel!: Option<String> = None,
        chatType!: Option<String> = None,
        normalizedKey!: Option<String> = None,
        rawKey!: String = ""
    ) {
        this.channel = channel
        this.chatType = chatType
        this.normalizedKey = normalizedKey
        this.rawKey = rawKey
    }
}

private func normalizeSessionKey(sessionKey: Option<String>): Option<String> {
    if (isSubagentSessionKey(sessionKey)) {
        return None
    }
    match (sessionKey) {
        case Some(raw) =>
            let trimmed = raw.trimAscii()
            if (trimmed.isEmpty()) {
                return None
            }
            match (parseAgentSessionKey(sessionKey)) {
                case Some(parsed) => Some(parsed.rest.trimAscii().toAsciiLower())
                case None => Some(trimmed.toAsciiLower())
            }
        case None => None
    }
}

public func deriveQmdScopeInfo(sessionKey: Option<String>): QmdScopeInfo {
    let raw = match (sessionKey) {
        case Some(value) => value.trimAscii().toAsciiLower()
        case None => ""
    }
    match (normalizeSessionKey(sessionKey)) {
        case Some(normalized) =>
            let parts = normalized.split(":")
            let channel: Option<String> = if (parts.size > 0 && !parts[0].trimAscii().isEmpty()) {
                Some(parts[0].trimAscii().toAsciiLower())
            } else {
                None<String>
            }
            if (normalized.contains(":group:")) {
                return QmdScopeInfo(channel: channel, chatType: Some("group"), normalizedKey: Some(normalized), rawKey: raw)
            }
            if (normalized.contains(":channel:")) {
                return QmdScopeInfo(channel: channel, chatType: Some("channel"), normalizedKey: Some(normalized), rawKey: raw)
            }
            if (normalized.contains(":dm:") || normalized.contains(":direct:") || normalized.contains(":peer:")) {
                return QmdScopeInfo(channel: channel, chatType: Some("direct"), normalizedKey: Some(normalized), rawKey: raw)
            }
            QmdScopeInfo(channel: channel, chatType: Some("direct"), normalizedKey: Some(normalized), rawKey: raw)
        case None =>
            QmdScopeInfo(rawKey: raw)
    }
}

public func deriveQmdScopeChannel(sessionKey: Option<String>): Option<String> {
    deriveQmdScopeInfo(sessionKey).channel
}

public func deriveQmdScopeChatType(sessionKey: Option<String>): Option<String> {
    deriveQmdScopeInfo(sessionKey).chatType
}

public func isQmdScopeAllowed(sessionKey: Option<String>): Bool {
    let info = deriveQmdScopeInfo(sessionKey)
    let normalizedChannel = info.channel ?? ""
    let normalizedChatType = info.chatType ?? ""
    let normalizedKey = info.normalizedKey ?? ""
    let rawKey = info.rawKey
    var idx: Int64 = 0
    while (idx < CliConfig.qmdScopeRuleActions.size) {
        let action = CliConfig.qmdScopeRuleActions[idx].trimAscii().toAsciiLower()
        let ruleChannel = if (idx < CliConfig.qmdScopeRuleChannels.size) { CliConfig.qmdScopeRuleChannels[idx].trimAscii().toAsciiLower() } else { "" }
        let ruleChatType = if (idx < CliConfig.qmdScopeRuleChatTypes.size) { CliConfig.qmdScopeRuleChatTypes[idx].trimAscii().toAsciiLower() } else { "" }
        let ruleKeyPrefix = if (idx < CliConfig.qmdScopeRuleKeyPrefixes.size) { CliConfig.qmdScopeRuleKeyPrefixes[idx].trimAscii().toAsciiLower() } else { "" }
        let ruleRawKeyPrefix = if (idx < CliConfig.qmdScopeRuleRawKeyPrefixes.size) { CliConfig.qmdScopeRuleRawKeyPrefixes[idx].trimAscii().toAsciiLower() } else { "" }
        if (!ruleChannel.isEmpty() && ruleChannel != normalizedChannel) {
            idx += 1
            continue
        }
        if (!ruleChatType.isEmpty() && ruleChatType != normalizedChatType) {
            idx += 1
            continue
        }
        if (!ruleRawKeyPrefix.isEmpty() && !rawKey.startsWith(ruleRawKeyPrefix)) {
            idx += 1
            continue
        }
        if (!ruleKeyPrefix.isEmpty() && !normalizedKey.startsWith(ruleKeyPrefix)) {
            idx += 1
            continue
        }
        return action == "allow" || action == "on"
    }
    let fallback = CliConfig.qmdScopeDefault.trimAscii().toAsciiLower()
    if (fallback.isEmpty()) {
        return true
    }
    fallback == "allow" || fallback == "all" || fallback == "on" || fallback == "enabled"
}
