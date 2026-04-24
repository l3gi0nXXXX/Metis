package metis.core.memory

import magic.core.message.{Conversation, ChatRound, Message, MessageList}

import metis.core.config.CliConfig

import std.fs.{File, exists, remove}
import std.unittest.testmacro.*

@Test
public class WorkspaceMemoryManagerTest {
    @TestCase
    public func saveConversationSnapshotUsesFlushPlanRelativePathAndPrompts(): Unit {
        let conversation = Conversation()
        conversation.addChatRound(
            ChatRound(
                Message.user("hello"),
                Message.assistant("world"),
                MessageList()
            )
        )
        let relativePath = "memory/test-flush.md"
        let targetPath = CliConfig.cwd.join(relativePath)
        try {
            if (exists(targetPath)) {
                remove(targetPath)
            }
            let written = WorkspaceMemoryManager.saveConversationSnapshot(
                conversation,
                reason: "compaction-preflush",
                relativePath: relativePath,
                prompt: "flush prompt",
                systemPrompt: "flush system"
            )
            @Expect(written, targetPath.toString())
            @Expect(exists(targetPath), true)
            let content = String.fromUtf8(File.readFrom(targetPath))
            @Expect(content.contains("## Memory Flush Prompt"), true)
            @Expect(content.contains("flush prompt"), true)
            @Expect(content.contains("## Memory Flush System Prompt"), true)
            @Expect(content.contains("flush system"), true)
            @Expect(content.contains("## Conversation"), true)
        } finally {
            if (exists(targetPath)) {
                remove(targetPath)
            }
        }
    }
}
