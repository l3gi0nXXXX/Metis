package metis.gateway.channels.builtin

import metis.gateway.core.ChannelAdapter
import metis.gateway.model.*
import metis.io.PrintUtils

import std.collection.ArrayList
import std.sync.Mutex

/**
 * 轻量内置渠道适配器。
 *
 * 目标不是一次性实现 Telegram/Slack/Discord 的完整协议，而是先把它们接入
 * Gateway 的默认 channel breadth：catalog、runtime、manager、bindings、status。
 * 当前发送行为为可观测的 stub，后续可以按各平台协议逐步替换。
 */
public class GenericBuiltinChannelAdapter <: ChannelAdapter {
    private let channelId: String
    private let label: String
    private let configured: Bool
    private let outboundLog = ArrayList<OutboundMessage>()
    private let inboundQueue = ArrayList<InboundMessage>()
    private let queueMutex = Mutex()
    private var running = false

    public init(channelId: String, label!: String = "", configured!: Bool = false) {
        this.channelId = channelId.trimAscii().toAsciiLower()
        this.label = if (label.trimAscii().isEmpty()) { this.channelId } else { label.trimAscii() }
        this.configured = configured
    }

    public prop name: String {
        get() { this.channelId }
    }

    public func start(): Unit {
        if (this.running) {
            return
        }
        this.running = true
        if (!this.configured) {
            PrintUtils.printLine("${this.label} adapter: started in stub mode (configuration incomplete).")
            return
        }
        PrintUtils.printLine("${this.label} adapter: started.")
    }

    public func stop(): Unit {
        this.running = false
    }

    public func pullInbound(): Array<InboundMessage> {
        synchronized(this.queueMutex) {
            if (!this.running || this.inboundQueue.isEmpty()) {
                return []
            }
            let result = this.inboundQueue.toArray()
            this.inboundQueue.clear()
            result
        }
    }

    public func send(message: OutboundMessage): SendResult {
        if (!this.running) {
            return SendResult.Failed("${this.channelId} adapter is not running")
        }
        synchronized(this.queueMutex) {
            this.outboundLog.add(message)
        }
        if (!this.configured) {
            return SendResult.Failed("${this.channelId} adapter is running in stub mode")
        }
        SendResult.Success
    }

    public func sendWithMessageId(message: OutboundMessage): String {
        match (this.send(message)) {
            case SendResult.Success => ""
            case SendResult.Failed(_reason) => ""
        }
    }
}
