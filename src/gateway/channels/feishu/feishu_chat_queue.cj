package metis.gateway.channels.feishu

import std.collection.HashMap
import std.sync.Mutex

public func buildFeishuQueueKey(accountId: String, chatId: String, threadId: String): String {
    let account = if (accountId.trimAscii().isEmpty()) { "default" } else { accountId.trimAscii() }
    let chat = chatId.trimAscii()
    let thread = threadId.trimAscii()
    if (thread.isEmpty()) {
        return "${account}:${chat}"
    }
    "${account}:${chat}:thread:${thread}"
}

class FeishuChatQueueSlot {
    let lock = Mutex()
    var depth: Int64 = 0
}

public class FeishuChatQueue {
    private let registryLock = Mutex()
    private let slots = HashMap<String, FeishuChatQueueSlot>()

    public init() {}

    public func runExclusive(accountId: String, chatId: String, threadId: String, task: () -> Unit): Unit {
        let key = buildFeishuQueueKey(accountId, chatId, threadId)
        let slot = synchronized(this.registryLock) {
            let existing = this.slots.get(key)
            let selected = match (existing) {
                case Some(v) => v
                case None =>
                    let created = FeishuChatQueueSlot()
                    this.slots[key] = created
                    created
            }
            selected.depth += 1
            selected
        }
        try {
            synchronized(slot.lock) {
                task()
            }
        } finally {
            synchronized(this.registryLock) {
                slot.depth -= 1
                if (slot.depth <= 0) {
                    this.slots.remove(key)
                }
            }
        }
    }
}
