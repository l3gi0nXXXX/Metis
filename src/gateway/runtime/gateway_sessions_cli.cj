package metis.gateway.runtime

import metis.core.config.{CliConfig, CliSettingManager, GatewayUserSettings}
import metis.gateway.core.{
    GatewaySessionConversationView,
    GatewaySessionStore,
    gatewayFindSessionLocationForUser,
    gatewayListSessionConversationViewsForUser,
    gatewayListPersistedAgentIdsForUser,
    gatewaySessionStoreForSessionKey,
    gatewaySessionStoreForUser,
    gatewaySessionStoreForUserWithAgentId
}

import metis.io.PrintUtils

import std.collection.ArrayList
import std.convert.Parsable
import std.fs.{Path, exists, Directory}

/**
 * `gateway sessions` subcommand for listing, reading, and deleting persisted
 * session transcripts under `~/.metis/agents/<agentId>/sessions`.
 */
public func runGatewaySessionsCli(sub: Array<String>): Int64 {
    let user = CliSettingManager.readGatewaySettings()
    if (sub.size < 2 || sub[1] == "help" || sub[1] == "-h" || sub[1] == "--help") {
        PrintUtils.printLine("Metis gateway sessions")
        PrintUtils.printLine("Inspect persisted gateway sessions.")
        PrintUtils.printLine("")
        PrintUtils.printLine("Usage:")
        PrintUtils.printLine("  gateway sessions <path|list|show|export|clear|delete|remove> [...]")
        PrintUtils.printLine("")
        PrintUtils.printLine("Commands:")
        PrintUtils.printLine("  gateway sessions path          Print the sessions directory path")
        PrintUtils.printLine("  gateway sessions list          List persisted session keys")
        PrintUtils.printLine("  gateway sessions show <key> [--limit <n>]")
        PrintUtils.printLine("                                      Preview one persisted session transcript")
        PrintUtils.printLine("  gateway sessions export <key>  Print the full raw JSONL transcript")
        PrintUtils.printLine("  gateway sessions clear <key>   Delete one persisted session transcript")
        PrintUtils.printLine("  gateway sessions delete <key>  Alias for clear")
        PrintUtils.printLine("  gateway sessions remove <key>  Alias for clear")
        return 0
    }

    let sc = sub[1].trimAscii().toAsciiLower()
    if (sc == "path") {
        for (line in gatewaySessionsPathLinesForUser(user)) {
            PrintUtils.printLine(line)
        }
        return 0
    }
    if (sc == "list") {
        for (line in gatewaySessionsListLinesForUser(user)) {
            PrintUtils.printLine(line)
        }
        return 0
    }
    if (sc == "show") {
        if (sub.size < 3) {
            PrintUtils.printLine("Usage: gateway sessions show <sessionKey-or-fileStem> [--limit <n>]")
            return 1
        }
        let parsed = parseGatewaySessionsShowArgs(sub, 2)
        let arg = parsed[0]
        let limit = parseGatewaySessionsShowLimit(parsed[1])
        if (arg.isEmpty()) {
            PrintUtils.printLine("Usage: gateway sessions show <sessionKey-or-fileStem> [--limit <n>]")
            return 1
        }
        let sessionStore = gatewaySessionStoreForSessionKey(user, arg)
        match (sessionStore.readTranscriptRaw(arg)) {
            case Some(raw) =>
                for (line in gatewaySessionsShowLinesForRaw(arg, raw, limit)) {
                    PrintUtils.printLine(line)
                }
            case None =>
                PrintUtils.printLine("Session not found: ${arg}")
                return 1
        }
        return 0
    }
    if (sc == "export") {
        if (sub.size < 3) {
            PrintUtils.printLine("Usage: gateway sessions export <sessionKey-or-fileStem>")
            return 1
        }
        let arg = joinGatewayCliArgsFrom(sub, 2)
        let sessionStore = gatewaySessionStoreForSessionKey(user, arg)
        match (sessionStore.readTranscriptRaw(arg)) {
            case Some(raw) => PrintUtils.printLine(raw)
            case None =>
                PrintUtils.printLine("Session not found: ${arg}")
                return 1
        }
        return 0
    }
    if (sc == "clear" || sc == "delete" || sc == "remove") {
        if (sub.size < 3) {
            PrintUtils.printLine("Usage: gateway sessions clear <sessionKey-or-fileStem>")
            return 1
        }
        let arg = joinGatewayCliArgsFrom(sub, 2)
        let sessionStore = gatewaySessionStoreForSessionKey(user, arg)
        if (sessionStore.deleteSession(arg)) {
            PrintUtils.printLine("Deleted: ${arg}")
            return 0
        }
        PrintUtils.printLine("Session not found or not deleted: ${arg}")
        return 1
    }

    PrintUtils.printLine("Unknown gateway sessions subcommand: ${sub[1]}")
    PrintUtils.printLine("Try: gateway sessions help")
    1
}

private let DEFAULT_GATEWAY_SESSIONS_SHOW_LIMIT: Int64 = 80

func gatewaySessionsShowLinesForUser(user: GatewayUserSettings, key: String, limit: Int64): Array<String> {
    let sessionStore = gatewaySessionStoreForSessionKey(user, key)
    match (sessionStore.readTranscriptRaw(key)) {
        case Some(raw) => gatewaySessionsShowLinesForRaw(key, raw, limit)
        case None =>
            let lines = ArrayList<String>()
            lines.add("Session not found: ${key}")
            lines.toArray()
    }
}

private func gatewaySessionsShowLinesForRaw(key: String, raw: String, limit: Int64): Array<String> {
    let lines = ArrayList<String>()
    let transcriptLines = gatewaySessionsTranscriptLines(raw)
    let cappedLimit = max(1, limit)
    let shown = min(cappedLimit, transcriptLines.size)
    lines.add("Transcript preview: ${key}")
    lines.add("Showing ${shown} of ${transcriptLines.size} JSONL line(s). Use `gateway sessions export ${key}` for the full raw transcript.")
    var i: Int64 = 0
    while (i < shown) {
        lines.add(transcriptLines[i])
        i += 1
    }
    if (shown < transcriptLines.size) {
        lines.add("... truncated ${transcriptLines.size - shown} line(s); rerun with `--limit <n>` or use `export`.")
    }
    lines.toArray()
}

private func gatewaySessionsTranscriptLines(raw: String): Array<String> {
    let out = ArrayList<String>()
    let split = raw.split("\n")
    for (i in 0..split.size) {
        if (i == split.size - 1 && split[i].isEmpty()) {
            continue
        }
        out.add(split[i])
    }
    out.toArray()
}

private func parseGatewaySessionsShowArgs(sub: Array<String>, start: Int64): Array<String> {
    let keyParts = ArrayList<String>()
    var limit = "${DEFAULT_GATEWAY_SESSIONS_SHOW_LIMIT}"
    var i = start
    while (i < sub.size) {
        let k = sub[i].trimAscii().toAsciiLower()
        if ((k == "--limit" || k == "-n") && i + 1 < sub.size) {
            limit = sub[i + 1].trimAscii()
            i += 2
            continue
        }
        keyParts.add(sub[i])
        i += 1
    }
    let key = String.join(keyParts.toArray(), delimiter: " ").trimAscii()
    [key, limit]
}

private func parseGatewaySessionsShowLimit(raw: String): Int64 {
    try {
        let n = Int64.parse(raw.trimAscii())
        if (n > 0) {
            return n
        }
    } catch (_: Exception) {
        ()
    }
    DEFAULT_GATEWAY_SESSIONS_SHOW_LIMIT
}

func gatewaySessionsPathLinesForUser(user: GatewayUserSettings): Array<String> {
    let lines = ArrayList<String>()
    let roots = gatewaySessionStorageRootsForUser(user)
    if (roots.size > 0) {
        for (root in roots) {
            lines.add(root)
        }
        return lines.toArray()
    }
    lines.add(gatewaySessionStoreForUser(user).sessionsRoot().toString())
    lines.toArray()
}

func gatewaySessionStorageRootsForUser(user: GatewayUserSettings): Array<String> {
    let roots = ArrayList<String>()
    for (agentId in gatewayListPersistedAgentIdsForUser(user)) {
        let root = gatewaySessionStoreForUserWithAgentId(user, agentId).sessionsRoot().toString()
        if (!roots.contains(root)) {
            roots.add(root)
        }
    }
    if (roots.size == 0) {
        roots.add(gatewaySessionStoreForUser(user).sessionsRoot().toString())
    }
    roots.toArray()
}

func gatewaySessionsListLinesForUser(user: GatewayUserSettings): Array<String> {
    let sessions = gatewayListSessionConversationViewsForUser(user)
    let lines = ArrayList<String>()
    lines.add("Workspace: ${CliConfig.cwd.toString()}")
    lines.add("Metis home: ${CliConfig.dotDir.toString()}")
    let roots = gatewaySessionStorageRootsForUser(user)
    lines.add("Sessions root: ${roots[0]}")
    if (roots.size > 1) {
        lines.add("Storage roots:")
        for (entry in roots) {
            lines.add("  - ${entry}")
        }
    }
    if (sessions.size > 0) {
        lines.add("Persisted sessions (${sessions.size}):")
        for (entry in sessions) {
            lines.add(gatewaySessionsCliFormatConversationView(entry))
        }
        return lines.toArray()
    }
    let root = Path(roots[0])
    if (!exists(root)) {
        lines.add(
            "No sessions directory exists yet. Enable gateway.session.persistenceEnabled and run gateway traffic to create persisted .jsonl transcripts."
        )
        return lines.toArray()
    }
    let jsonlCount = gatewaySessionsCountJsonlFiles(root)
    if (jsonlCount == 0) {
        lines.add(
            "No persisted session files were found. The directory exists, but it does not contain any .jsonl transcripts yet."
        )
    } else {
        lines.add(
            "Found ${jsonlCount} .jsonl file(s), but none exposed a valid meta.sessionKey on the first line. Inspect the directory or try gateway sessions show <file-stem>."
        )
    }
    lines.toArray()
}

func gatewaySessionsCliFormatConversationView(entry: GatewaySessionConversationView): String {
    let summary = if (!entry.displayName.isEmpty() && entry.displayName != entry.key) {
        " ${entry.displayName}"
    } else {
        ""
    }
    let channel = if (!entry.channel.isEmpty()) {
        " channel=${entry.channel}"
    } else {
        ""
    }
    let kind = if (!entry.chatType.isEmpty()) {
        " kind=${entry.chatType}"
    } else {
        ""
    }
    let peer = if (!entry.peer.isEmpty()) {
        " peer=${entry.peer}"
    } else {
        ""
    }
    let sessionId = if (!entry.sessionId.isEmpty()) {
        " sessionId=${entry.sessionId}"
    } else {
        ""
    }
    "  - [${entry.agentId}] ${entry.key}${summary}${channel}${kind}${peer}${sessionId}"
}

private func gatewaySessionsCountJsonlFiles(dir: Path): Int64 {
    if (!exists(dir)) {
        return 0
    }
    var n: Int64 = 0
    try {
        for (entry in Directory.readFrom(dir)) {
            if (entry.isRegular() && entry.name.endsWith(".jsonl")) {
                n += 1
            }
        }
    } catch (_e: Exception) {
        return 0
    }
    n
}

private func joinGatewayCliArgsFrom(parts: Array<String>, start: Int64): String {
    if (start >= parts.size) {
        return ""
    }
    var s = parts[start]
    var i = start + 1
    while (i < parts.size) {
        s = s + " " + parts[i]
        i += 1
    }
    s
}
