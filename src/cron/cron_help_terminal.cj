package metis.cron

import metis.io.AnsiColor

import std.collection.ArrayList
import std.env.getVariable

/** 与常见 CLI 帮助一致：章节标题偏橘、开关名为亮黄、正文默认色。 */
private let cronHelpSectionColor = AnsiColor.color256(208)
private let cronHelpFlagColor = AnsiColor.BRIGHT_YELLOW

public func cronHelpTerminalColorsWanted(): Bool {
    match (getVariable("NO_COLOR")) {
        case Some(_) => false
        case None => true
    }
}

/**
 * 为 `gateway cron ... --help` 类输出加上 ANSI 颜色（尊重 NO_COLOR）。
 */
public func formatCronHelpForTerminal(raw: String): String {
    if (!cronHelpTerminalColorsWanted()) {
        return raw
    }
    let lines = raw.split("\n")
    let out = ArrayList<String>()
    for (ln in lines) {
        out.add(colorizeCronHelpTerminalLine(ln))
    }
    String.join(out.toArray(), delimiter: "\n")
}

private func colorizeCronHelpTerminalLine(line: String): String {
    if (line.isEmpty()) {
        return line
    }
    let runes = line.toRuneArray()
    var lead: Int64 = 0
    while (lead < runes.size && runes[lead] == r' ') {
        lead += 1
    }
    let prefix = String(runes[0..lead])
    let content = String(runes[lead..runes.size])
    if (content.isEmpty()) {
        return line
    }
    if (content.startsWith("Usage:")) {
        return "${prefix}${cronHelpSectionColor}Usage:${AnsiColor.RESET}${content[6..content.size]}"
    }
    if (content == "Options:" || content.startsWith("Options:")) {
        return "${prefix}${cronHelpSectionColor}Options:${AnsiColor.RESET}${content[8..content.size]}"
    }
    if (content == "Arguments:" || content.startsWith("Arguments:")) {
        return "${prefix}${cronHelpSectionColor}Arguments:${AnsiColor.RESET}${content[11..content.size]}"
    }
    if (cronHelpLineLooksLikeFlagRow(content)) {
        let rr = content.toRuneArray()
        var gap: Int64 = -1
        var j: Int64 = 0
        while (j < rr.size - 1) {
            if (rr[j] == r' ' && rr[j + 1] == r' ') {
                gap = j
                break
            }
            j += 1
        }
        if (gap >= 0) {
            let flagPart = String(rr[0..gap])
            let tail = String(rr[gap..rr.size])
            return "${prefix}${cronHelpFlagColor}${flagPart}${AnsiColor.RESET}${tail}"
        }
        return "${prefix}${cronHelpFlagColor}${content}${AnsiColor.RESET}"
    }
    line
}

private func cronHelpLineLooksLikeFlagRow(content: String): Bool {
    if (content.startsWith("--")) {
        return true
    }
    if (content.startsWith("<")) {
        return true
    }
    if (content.size >= 2 && content[0..1] == "-" && content[1..2] != "-") {
        let r1 = content[1..2].toRuneArray()
        if (r1.size == 1) {
            let c = r1[0]
            if ((c >= r'a' && c <= r'z') || (c >= r'A' && c <= r'Z')) {
                return true
            }
        }
    }
    false
}
