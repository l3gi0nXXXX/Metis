package metis.gateway.core

import metis.gateway.model.{InboundMessage, OutboundMessage, SendResult}

/**
 * 渠道适配器统一接口。
 * 所有渠道（飞书、QQ、钉钉等）都应实现该接口，确保 Gateway 核心可复用。
 */
public interface ChannelAdapter {
    /**
     * 适配器名。建议与 channelToString 一致，便于日志和映射。
     */
    prop name: String

    /**
     * 启动渠道连接（例如建立 WebSocket 或启动 webhook server）。
     */
    func start(): Unit

    /**
     * 关闭渠道连接并释放资源。
     */
    func stop(): Unit

    /**
     * 从渠道适配器中批量拉取尚未处理的入站消息。
     * P0 采用 pull 模型，避免引入额外并发复杂度。
     */
    func pullInbound(): Array<InboundMessage>

    /**
     * 发送消息到渠道。
     */
    func send(message: OutboundMessage): SendResult

    /**
     * 发送消息并在渠道支持时返回已发送消息 ID。
     * 不支持编辑式流式更新的渠道可返回空字符串。
     */
    func sendWithMessageId(message: OutboundMessage): String
}
