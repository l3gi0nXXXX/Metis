package metis.core.conversation

import magic.agent.ConversationAgent
import magic.core.message.Conversation
import magic.log.LogUtils

import metis.io.PrintUtils
import metis.core.config.CliConfig
import metis.core.agents.CliConversationCompactor
import metis.core.memory.{WorkspaceMemoryManager, MemoryStateRegistry, resolveMemoryFlushPlan}

import std.fs.{exists, Directory, Path, remove, FSException}
import std.collection.*
import std.sort.sort
import std.time.DateTime

/**
 * Handles all conversation operations including save, resume, list, and remove
 */
protected class ConversationManager {
    public static let AUTO_SAVE_NAME = "last-conversation"

    protected let conversation = Conversation()
    private let compactor: CliConversationCompactor

    public init(compactor: CliConversationCompactor) {
        this.compactor = compactor
    }

    public func handleCommand(args: Array<String>): Unit {
        if (args.size < 2) {
            listConversations()
            return
        }

        let subCommand = args[1].trimAscii()
        match (subCommand) {
            case "list" => listConversations()
            case "save" =>
                if (args.size < 3) {
                    PrintUtils.printLine("Error: Please provide a name for the conversation.\nUsage: /conversation save <name>")
                } else {
                    saveConversation(args[2].trimAscii())
                }
            case "resume" | "load" =>
                if (args.size < 3) {
                    PrintUtils.printLine(
                        "Error: Please provide the name of the conversation to resume.\nUsage: /conversation resume <name>")
                } else {
                    resumeConversation(args[2].trimAscii())
                }
            case "remove" | "delete" =>
                if (args.size < 3) {
                    PrintUtils.printLine(
                        "Error: Please provide the name of the conversation to delete.\nUsage: /conversation remove <name>")
                } else {
                    removeConversation(args[2].trimAscii())
                }
            case "help" => showHelpText()
            case _ =>
                PrintUtils.printLine("Unknown subcommand: ${subCommand}")
                showHelpText()
        }
    }

    /**
     * Auto-save conversation on exit
     */
    public func autoSave(): Unit {
        ensureHistoryDirectory()
        let filePath = getConversationPath(AUTO_SAVE_NAME)
        try {
            this.conversation.save(filePath)
        } catch (e: Exception) {
            LogUtils.error("Failed to auto-save conversation: ${e.message}")
        }
    }

    /**
     * Clear current conversation
     */
    public func clearConversation(): Unit {
        let memoryPath = WorkspaceMemoryManager.saveConversationSnapshot(this.conversation, reason: "clear")
        this.conversation.clear()
        this.refreshMemoryIndex()
        if (!memoryPath.isEmpty()) {
            PrintUtils.printLine("💾 Session snapshot saved to ${memoryPath}")
        }
        PrintUtils.printLine("✅ Conversation history cleared")
    }

    private func listConversations(): Unit {
        let conversations = getSavedConversations()
        if (conversations.size == 0) {
            PrintUtils.printLine("No saved conversations found.")
            return
        }

        PrintUtils.printLine("📚 Available Conversations:")
        for (convName in conversations) {
            if (convName == AUTO_SAVE_NAME) {
                PrintUtils.printLine("  • ${convName} (auto-saved conversation)")
            } else {
                PrintUtils.printLine("  • ${convName}")
            }
        }
        PrintUtils.printLine("\nUse '/conversation resume <name>' to load a conversation")
    }

    private func saveConversation(name: String): Unit {
        if (name.isEmpty()) {
            PrintUtils.printLine("Error: Conversation name cannot be empty.")
            return
        }

        if (name == AUTO_SAVE_NAME) {
            PrintUtils.printLine(
                "Error: '${AUTO_SAVE_NAME}' is reserved for auto-saved conversations. Please choose a different name.")
            return
        }

        if (!isValidName(name)) {
            PrintUtils.printLine("Error: Invalid conversation name. Name cannot contain: < > : \" / \\ | ? *")
            return
        }

        try {
            ensureHistoryDirectory()
            let filePath = getConversationPath(name)
            this.conversation.save(filePath)
            PrintUtils.printLine("✅ Conversation saved as '${name}'")
        } catch (e: Exception) {
            PrintUtils.printLine("❌ Failed to save conversation '${name}': ${e.message}")
        }
    }

    private func resumeConversation(name: String): Unit {
        if (name.isEmpty()) {
            PrintUtils.printLine("Error: Conversation name cannot be empty.")
            return
        }

        let filePath = getConversationPath(name)
        if (!exists(filePath)) {
            PrintUtils.printLine("❌ Conversation '${name}' not found.")
            listConversations()
            return
        }

        try {
            let loadedConversation = Conversation.load(filePath)
            this.conversation.clear()
            for (chatRound in loadedConversation) {
                this.conversation.addChatRound(chatRound)
            }

            if (name == AUTO_SAVE_NAME) {
                PrintUtils.printLine("✅ Last conversation resumed successfully!")
            } else {
                PrintUtils.printLine("✅ Conversation '${name}' resumed successfully!")
            }
        } catch (e: Exception) {
            PrintUtils.printLine("❌ Failed to load conversation '${name}': ${e.message}")
        }
    }

    private func removeConversation(name: String): Unit {
        if (name.isEmpty()) {
            PrintUtils.printLine("Error: Conversation name cannot be empty.")
            return
        }

        if (name == AUTO_SAVE_NAME) {
            PrintUtils.printLine("Error: Cannot delete the auto-saved session. It will be overwritten on next exit.")
            return
        }

        let filePath = getConversationPath(name)
        if (!exists(filePath)) {
            PrintUtils.printLine("❌ Conversation '${name}' does not exist.")
            return
        }

        try {
            remove(filePath)
            PrintUtils.printLine("✅ Conversation '${name}' deleted successfully")
        } catch (e: FSException) {
            PrintUtils.printLine("❌ Failed to delete conversation '${name}': ${e.message}")
        }
    }

    private func getSavedConversations(): Array<String> {
        let historyDir = CliConfig.conversationHistoryDir
        if (!exists(historyDir)) {
            return []
        }

        let conversations = ArrayList<String>()

        try {
            for (entry in Directory.readFrom(historyDir)) {
                if (entry.isRegular()) {
                    let fileName = entry.name
                    if (fileName.endsWith(".history")) {
                        let nameWithoutExt = fileName.replace(".history", "")
                        conversations.add(nameWithoutExt)
                    }
                }
            }
        } catch (e: FSException) {
            LogUtils.error("Failed to list conversations: ${e.message}")
        }

        let result = conversations.toArray()
        sort(result)
        return result
    }

    public func compact(manual!: Bool = false): Unit {
        if (let Some(index) <- this.compactor.calculateCompactIndex(this.conversation)) {
            PrintUtils.printProcedure("Compacting conversation...", "🚀 Working on it...")
            let flushPlan = resolveMemoryFlushPlan(
                nowMs: DateTime.now().toUnixTimeStamp().toMilliseconds()
            )
            let memoryPath = WorkspaceMemoryManager.saveConversationSnapshot(
                this.conversation,
                reason: "compaction-preflush",
                relativePath: match (flushPlan) {
                    case Some(plan) => plan.relativePath
                    case None => ""
                },
                prompt: match (flushPlan) {
                    case Some(plan) => plan.prompt
                    case None => ""
                },
                systemPrompt: match (flushPlan) {
                    case Some(plan) => plan.systemPrompt
                    case None => ""
                }
            )
            this.conversation.compactBy(compactor, firstN: index, keepOrigin: false)
            this.refreshMemoryIndex()
            if (!memoryPath.isEmpty()) {
                PrintUtils.printLine("💾 Memory preflush saved to ${memoryPath}")
            }
            PrintUtils.printProcedure("Compacting conversation...", "🥳 Compacted successfully!")
        } else if (manual) {
            PrintUtils.printProcedure("Compacting conversation...",
                "🌱 Conversation context is short enough, no need to compact!")
        }
    }

    private func refreshMemoryIndex(): Unit {
        let indexPath = MemoryStateRegistry.writeIndexSnapshot(purpose: "conversation-refresh-index")
        if (indexPath.isEmpty()) {
            LogUtils.error("Failed to refresh local memory index")
        }
    }

    private func ensureHistoryDirectory(): Unit {
        let historyDir = CliConfig.conversationHistoryDir
        if (!exists(historyDir)) {
            try {
                Directory.create(historyDir, recursive: true)
            } catch (e: FSException) {
                LogUtils.error("Failed to create conversation history directory: ${e.message}")
            }
        }
    }

    private func getConversationPath(name: String): Path {
        return CliConfig.conversationHistoryDir.join("${name}.history")
    }

    private func isValidName(name: String): Bool {
        if (name.isEmpty()) {
            return false
        }
        let invalidChars = ["<", ">", ":", "\"", "/", "\\", "|", "?", "*"]
        for (char in invalidChars) {
            if (name.contains(char)) {
                return false
            }
        }
        return true
    }

    private func showHelpText(): Unit {
        PrintUtils.printLine(
            """
📖 Conversation Management Commands:
  /conversation                      - List all saved conversations
  /conversation list                 - List all saved conversations
  /conversation save <name>          - Save current conversation
  /conversation resume <name>        - Load a saved conversation
  /conversation remove <name>        - Delete a saved conversation
  /conversation help                 - Show this help""")
    }
}
