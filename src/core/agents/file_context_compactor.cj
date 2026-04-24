package metis.core.agents

import magic.core.message.Conversation
import magic.log.LogUtils

import metis.core.config.CliConfig

import std.fs.{Path, canonicalize}
import std.time.DateTime
import std.random.Random

/**
 * Compactor that archives the full pre-compaction conversation snapshot
 * and appends the archive path to the compact summary.
 */
public class FileContextCompactor <: CliConversationCompactor {
    private let baseCompactor = Compactor()

    override public func compact(conversation: Conversation): String {
        var archivePath: Option<String> = None
        var archiveError: Option<String> = None

        try {
            let savedPath = this.archiveConversation(conversation)
            archivePath = Some(savedPath.toString())
        } catch (ex: Exception) {
            archiveError = Some(ex.message)
            LogUtils.error("Failed to archive compacted conversation: ${ex.message}")
        }

        let summary = this.baseCompactor.compact(conversation)
        return summary + this.buildArchiveSection(archivePath, archiveError)
    }

    private func archiveConversation(conversation: Conversation): Path {
        let fileName = this.buildArchiveFileName()
        let filePath = CliConfig.conversationArchiveDir.join(fileName)
        conversation.save(filePath)
        return canonicalize(filePath.toString())
    }

    private func buildArchiveFileName(): String {
        let ts = DateTime.now().format("yyyy_MM_dd-HH_mm_ss_SSS")
        let suffix = this.randomHex(8)
        return "compact-${ts}-${suffix}.json"
    }

    private func randomHex(count: Int64): String {
        let rand = Random()
        let chars = "0123456789abcdef".toRuneArray()
        let result = StringBuilder()
        for (_ in 0..count) {
            let raw = rand.nextInt64()
            let idx = Int64((raw % chars.size + chars.size) % chars.size)
            result.append(chars[idx])
        }
        return result.toString()
    }

    private func buildArchiveSection(path: Option<String>, reason: Option<String>): String {
        if (let Some(p) <- path) {
            return "\n<history_archive><path>${this.xmlEscape(p)}</path><format>conversation_json</format></history_archive>"
        }
        let escapedReason = this.xmlEscape(reason ?? "unknown_error")
        return "\n<history_archive><status>unavailable</status><reason>${escapedReason}</reason></history_archive>"
    }

    override public func calculateCompactIndex(conversation: Conversation): Option<Int64> {
        if (conversation.size <= 1) {
            return None
        }

        if (let Some(index) <- this.baseCompactor.calculateCompactIndex(conversation)) {
            if (index <= 0) {
                return None
            }
            // Always keep at least the latest chat round uncompressed.
            if (index >= conversation.size) {
                return Some(conversation.size - 1)
            }
            return Some(index)
        }
        return None
    }

    private func xmlEscape(value: String): String {
        return value
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")
            .replace("'", "&apos;")
    }
}
