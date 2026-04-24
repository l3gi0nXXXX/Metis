package metis.io

import metis.utils.RegexUtils

import std.regex.*
import std.collection.*

public func renderMarkdown(content: String): String {
    let lines = content.split("\n")
    let result = ArrayList<String>()
    var inCodeBlock = false
    var codeLanguage = ""

    for (line in lines) {
        if (!inCodeBlock) {
            // Check for code block start
            if (line.startsWith("```")) {
                inCodeBlock = true
                codeLanguage = line[3..].trimAscii()
                result.add("${AnsiColor.BG_BLACK}${AnsiColor.BRIGHT_WHITE} ${line} ${AnsiColor.RESET}")
                continue
            }

            // Process regular line
            let processedLine = processInlineMarkdown(line)
            result.add(processedLine)
        } else {
            // Inside code block
            if (line == "```") {
                inCodeBlock = false
                result.add("${AnsiColor.BG_BLACK}${AnsiColor.BRIGHT_WHITE} ${line} ${AnsiColor.RESET}")
            } else {
                // Code block content - use different styling
                result.add("${AnsiColor.BRIGHT_BLACK}${line}${AnsiColor.RESET}")
            }
        }
    }

    return String.join(result.toArray(), delimiter: "\n")
}

private func processInlineMarkdown(line: String): String {
    var processed = line

    // Headers (# ## ###)
    processed = RegexUtils.replaceAll(processed, #"(#{1,6})\s+(.+)$"#, { m =>
        let header = m.matchString(1)
        let level = header.size
        let text = m.matchString(2)
        let color = match (level) {
            case 1 => AnsiColor.BRIGHT_CYAN
            case 2 => AnsiColor.CYAN
            case 3 => AnsiColor.BRIGHT_BLUE
            case 4 => AnsiColor.BLUE
            case 5 => AnsiColor.MAGENTA
            case _ => AnsiColor.MAGENTA
        }
        "${header.withColor(Theme.MUTED)} ${color}${text}${AnsiColor.RESET}"
    })

    // Bold (**text** or __text__)
    processed = RegexUtils.replaceAll(processed, #"\*\*([^*]+)\*\*"#, { m =>
        "${AnsiColor.BOLD}${m.matchString(1)}${AnsiColor.RESET}"
    })
    processed = RegexUtils.replaceAll(processed, #"__([^_]+)__"#, { m =>
        "${AnsiColor.BOLD}${m.matchString(1)}${AnsiColor.RESET}"
    })

    // Italic (*text* or _text_)
    processed = RegexUtils.replaceAll(processed, #"\*([^*]+)\*"#, { m =>
        "${AnsiColor.ITALIC}${m.matchString(1)}${AnsiColor.RESET}"
    })
    processed = RegexUtils.replaceAll(processed, #"_([^_]+)_"#, { m =>
        "${AnsiColor.ITALIC}${m.matchString(1)}${AnsiColor.RESET}"
    })

    // Bold + Italic (***text*** or ___text___)
    processed = RegexUtils.replaceAll(processed, #"\*\*\*([^*]+)\*\*\*"#, { m =>
        "${AnsiColor.BOLD}${AnsiColor.ITALIC}${m.matchString(1)}${AnsiColor.RESET}"
    })
    processed = RegexUtils.replaceAll(processed, #"___([^_]+)___"#, { m =>
        "${AnsiColor.BOLD}${AnsiColor.ITALIC}${m.matchString(1)}${AnsiColor.RESET}"
    })

    // Inline code (`code`)
    processed = RegexUtils.replaceAll(processed, #"`([^`]+)`"#, { m =>
        "${AnsiColor.BG_BLACK}${AnsiColor.BRIGHT_YELLOW}${m.matchString(1)}${AnsiColor.RESET}"
    })

    // Strike through (~~text~~)
    processed = RegexUtils.replaceAll(processed, #"~~([^~]+)~~"#, { m =>
        "${AnsiColor.STRIKE_THROUGH}${m.matchString(1)}${AnsiColor.RESET}"
    })

    // Links [text](url)
    processed = RegexUtils.replaceAll(processed, #"\[([^\]]+)\]\(([^)]+)\)"#, { m =>
        let text = m.matchString(1)
        let url = m.matchString(2)
        "${AnsiColor.UNDERLINE}${AnsiColor.BRIGHT_BLUE}${text}${AnsiColor.RESET} (${AnsiColor.GREEN}${url}${AnsiColor.RESET})"
    })

    // Unordered lists (- or * or +)
    processed = RegexUtils.replaceAll(processed, #"^\s*([-*+])\s+(.+)$"#, { m =>
        let bullet = m.matchString(1)
        let text = m.matchString(2)
        "${AnsiColor.BRIGHT_GREEN}${bullet}${AnsiColor.RESET} ${text}"
    })

    // Ordered lists (1. 2. etc)
    processed = RegexUtils.replaceAll(processed, #"^\s*(\d+\.)\s+(.+)$"#, { m =>
        let number = m.matchString(1)
        let text = m.matchString(2)
        "${AnsiColor.BRIGHT_GREEN}${number}${AnsiColor.RESET} ${text}"
    })

    // Blockquotes (>)
    processed = RegexUtils.replaceAll(processed, #"^\s*(>+)\s*(.+)$"#, { m =>
        let level = m.matchString(1).size
        let text = m.matchString(2)
        let color = match (level) {
            case 1 => AnsiColor.BRIGHT_BLACK
            case 2 => AnsiColor.DIM
            case _ => AnsiColor.DIM
        }
        "${color}> ${text}${AnsiColor.RESET}"
    })

    return processed
}