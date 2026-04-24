package metis.core.memory

import magic.core.message.Conversation
import magic.log.LogUtils

import metis.core.config.CliConfig

import std.collection.ArrayList
import std.fs.{Directory, File, exists, OpenMode, Path}
import std.time.DateTime

public class WorkspaceMemoryManager {
    public static func saveConversationSnapshot(
        conversation: Conversation,
        reason!: String = "session",
        relativePath!: String = "",
        prompt!: String = "",
        systemPrompt!: String = ""
    ): String {
        if (conversation.size == 0) {
            return ""
        }

        let memoryDir = CliConfig.cwd.join("memory")
        try {
            if (!exists(memoryDir)) {
                Directory.create(memoryDir, recursive: true)
            }

            let now = DateTime.now()
            let datePart = now.format("yyyy-MM-dd")
            let timePart = now.format("HHmm")
            let safeReason = sanitizeReason(reason)
            let filePath = resolveSnapshotPath(
                memoryDir,
                datePart,
                timePart,
                safeReason,
                relativePath
            )
            let parentDir = filePath.parent
            if (!exists(parentDir)) {
                Directory.create(parentDir, recursive: true)
            }

            let lines = ArrayList<String>()
            lines.add("# Session: ${now.format("yyyy-MM-dd HH:mm:ss")}")
            lines.add("")
            lines.add("- **Reason**: ${safeReason}")
            lines.add("- **Workspace**: ${CliConfig.cwd}")
            lines.add("")
            let trimmedPrompt = prompt.trimAscii()
            let trimmedSystemPrompt = systemPrompt.trimAscii()
            if (!trimmedPrompt.isEmpty()) {
                lines.add("## Memory Flush Prompt")
                lines.add("")
                lines.add(trimmedPrompt)
                lines.add("")
            }
            if (!trimmedSystemPrompt.isEmpty()) {
                lines.add("## Memory Flush System Prompt")
                lines.add("")
                lines.add(trimmedSystemPrompt)
                lines.add("")
            }
            lines.add("## Conversation")
            lines.add("")
            for (chatRound in conversation) {
                lines.add(chatRound.toString())
                lines.add("")
            }

            File.writeTo(filePath, String.join(lines.toArray(), delimiter: "\n").toArray())
            appendDailyMemoryRollup(memoryDir, now, safeReason, conversation)
            return filePath.toString()
        } catch (e: Exception) {
            LogUtils.error("Failed to save workspace memory snapshot: ${e.message}")
            return ""
        }
    }
}

private func sanitizeReason(reason: String): String {
    let trimmed = reason.trimAscii().toAsciiLower()
    if (trimmed.isEmpty()) {
        return "session"
    }
    let normalized = trimmed.replace(" ", "-").replace("/", "-").replace("\\", "-").replace(":", "-")
    if (normalized.isEmpty()) {
        return "session"
    }
    normalized
}

private func resolveSnapshotPath(
    memoryDir: Path,
    datePart: String,
    timePart: String,
    safeReason: String,
    relativePath: String
): Path {
    let trimmed = relativePath.trimAscii()
    if (trimmed.isEmpty()) {
        return memoryDir.join("${datePart}-${timePart}-${safeReason}.md")
    }
    var normalized = trimmed.replace("\\", "/").replace("..", "").trimAscii()
    while (normalized.startsWith("/")) {
        normalized = normalized[1..]
    }
    if (normalized.startsWith("memory/")) {
        normalized = normalized["memory/".size..]
    }
    if (normalized.isEmpty()) {
        return memoryDir.join("${datePart}-${timePart}-${safeReason}.md")
    }
    memoryDir.join(normalized)
}

private func appendDailyMemoryRollup(
    memoryDir: Path,
    now: DateTime,
    reason: String,
    conversation: Conversation
): Unit {
    let dailyPath = memoryDir.join("${now.format("yyyy-MM-dd")}.md")
    let lines = ArrayList<String>()
    lines.add("")
    lines.add("## ${now.format("HH:mm")} ${reason}")
    lines.add("")
    lines.add("- Reason: ${reason}")
    lines.add("- Workspace: ${CliConfig.cwd}")
    lines.add("- Rounds: ${conversation.size}")
    for (chatRound in conversation) {
        let summary = summarizeChatRound(chatRound.toString())
        if (!summary.isEmpty()) {
            lines.add("- ${summary}")
        }
    }
    lines.add("")
    try {
        if (!exists(dailyPath)) {
            File.writeTo(dailyPath, "# ${now.format("yyyy-MM-dd")}\n".toArray())
        }
        try (file = File(dailyPath, OpenMode.Append)) {
            file.write(String.join(lines.toArray(), delimiter: "\n").toArray())
        }
    } catch (e: Exception) {
        LogUtils.error("Failed to append daily workspace memory rollup: ${e.message}")
    }
}

private func summarizeChatRound(text: String): String {
    let flattened = text
        .replace("\r\n", " ")
        .replace("\n", " ")
        .replace("\r", " ")
        .replace("\t", " ")
        .trimAscii()
    if (flattened.isEmpty()) {
        return ""
    }
    let compact = flattened.replace("  ", " ")
    if (compact.size <= 220) {
        return compact
    }
    compact[0..220] + "..."
}
