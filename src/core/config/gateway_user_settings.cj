package metis.core.config

import magic.dsl.jsonable
import magic.jsonable.*

import stdx.encoding.json.*
import std.collection.{HashMap, ArrayList}

/**
 * 网关 Agent 工具策略：`tools.allow` / `tools.deny`，deny 优先。
 *
 * - `allow` 为空：允许所有已注册的网关内置工具（由实现决定列表）。
 * - `allow` 非空：仅允许白名单中的工具名（仍受 `deny` 约束）。
 * - `deny`：禁止的工具名；含 `"*"` 时拒绝所有网关工具。
 */
@jsonable
public struct GatewayToolsUserSettings {
    public var allow: Array<String> = []
    public var deny: Array<String> = []
}

/**
 * Subagent 启动策略与资源上限。
 *
 * 默认值保持已有 `sessions_spawn` 能力可用；显式禁用、黑白名单或超限时在创建
 * 子 session 前拒绝启动，避免产生半成品转录和 run record。
 */
@jsonable
public struct GatewaySubagentPolicyUserSettings {
    public var enabled: Bool = true
    public var allowAgents: Array<String> = []
    public var denyAgents: Array<String> = []
    public var requireAgentId: Bool = false
    public var maxConcurrentSubagents: Int64 = 4
    public var maxChildrenPerSession: Int64 = 8
    public var maxSpawnDepth: Int64 = 1
    public var defaultTimeoutSeconds: Int64 = 600
    public var maxTimeoutSeconds: Int64 = 1800
    public var childAllowedTools: Array<String> = []
    public var childDeniedTools: Array<String> = []
    public var allowCustomAgents: Bool = false
    public var allowWriteAgents: Bool = false
    public var requireWorktreeForWriteAgents: Bool = true
}

@jsonable
public struct GatewayTlsUserSettings {
    public var enabled: Bool = false
    public var autoGenerate: Bool = true
    public var certPath: String = ""
    public var keyPath: String = ""
    public var caPath: String = ""
}

@jsonable
public struct GatewayWideAreaDiscoveryUserSettings {
    public var enabled: Bool = false
    public var domain: String = ""
}

@jsonable
public struct GatewayMdnsDiscoveryUserSettings {
    public var mode: String = "minimal"
}

@jsonable
public struct GatewayDiscoveryUserSettings {
    public var wideArea: GatewayWideAreaDiscoveryUserSettings = GatewayWideAreaDiscoveryUserSettings()
    public var mdns: GatewayMdnsDiscoveryUserSettings = GatewayMdnsDiscoveryUserSettings()
}

@jsonable
public struct GatewayCanvasHostUserSettings {
    public var enabled: Bool = false
    public var root: String = ""
    public var port: Int64 = 18793
    public var liveReload: Bool = true
}

@jsonable
public struct GatewayTalkUserSettings {
    public var provider: String = ""
    public var providers: Option<JsonObject> = None
    public var interruptOnSpeech: Bool = true
    public var silenceTimeoutMs: Int64 = 1200
}

@jsonable
public struct GatewaySpeechUserSettings {
    public var tts: JsonObject = JsonObject()
    public var asr: JsonObject = JsonObject()
}

@jsonable
public struct GatewayMediaUserSettings {
    public var image: JsonObject = JsonObject()
    public var video: JsonObject = JsonObject()
    public var videoGeneration: JsonObject = JsonObject()
    public var imageGeneration: JsonObject = JsonObject()
}

@jsonable
public struct GatewayChannelSpeechUserSettings {
    public var tts: JsonObject = JsonObject()
    public var asr: JsonObject = JsonObject()
    public var audioAsVoice: Option<Bool> = None<Bool>
    public var autoReplyToVoice: Option<Bool> = None<Bool>
}

@jsonable
public struct GatewayControlUiUserSettings {
    public var enabled: Bool = true
    public var basePath: String = ""
    public var root: String = ""
    public var allowedOrigins: Array<String> = []
    public var dangerouslyAllowHostHeaderOriginFallback: Bool = false
    public var allowInsecureAuth: Bool = false
    public var dangerouslyDisableDeviceAuth: Bool = false
}

@jsonable
public struct GatewayTrustedProxyUserSettings {
    public var userHeader: String = ""
    public var requiredHeaders: Array<String> = []
    public var allowUsers: Array<String> = []
}

@jsonable
public struct GatewayAuthRateLimitUserSettings {
    public var maxAttempts: Int64 = 10
    public var windowMs: Int64 = 60000
    public var lockoutMs: Int64 = 300000
    public var exemptLoopback: Bool = true
}

@jsonable
public struct GatewayAuthUserSettings {
    public var mode: String = "token"
    public var token: String = ""
    public var password: String = ""
    public var allowTailscale: Bool = false
    public var rateLimit: GatewayAuthRateLimitUserSettings = GatewayAuthRateLimitUserSettings()
    public var trustedProxy: GatewayTrustedProxyUserSettings = GatewayTrustedProxyUserSettings()
}

@jsonable
public struct GatewayTailscaleUserSettings {
    public var mode: String = "off"
    public var resetOnExit: Bool = false
}

@jsonable
public struct GatewayRemoteUserSettings {
    public var enabled: Bool = false
    public var url: String = ""
    public var transport: String = "ssh"
    public var token: String = ""
    public var password: String = ""
    public var tlsFingerprint: String = ""
    public var sshTarget: String = ""
    public var sshIdentity: String = ""
}

@jsonable
public struct GatewayReloadUserSettings {
    public var mode: String = "hybrid"
    public var debounceMs: Int64 = 300
    public var deferralTimeoutMs: Int64 = 300000
}

@jsonable
public struct GatewayHttpChatCompletionsImagesUserSettings {
    public var allowUrl: Bool = false
    public var urlAllowlist: Array<String> = []
    public var allowedMimes: Array<String> = []
    public var maxBytes: Int64 = 10 * 1024 * 1024
    public var maxRedirects: Int64 = 3
    public var timeoutMs: Int64 = 10000
}

@jsonable
public struct GatewayHttpChatCompletionsUserSettings {
    public var enabled: Bool = false
    public var maxBodyBytes: Int64 = 20 * 1024 * 1024
    public var maxImageParts: Int64 = 8
    public var maxTotalImageBytes: Int64 = 20 * 1024 * 1024
    public var images: GatewayHttpChatCompletionsImagesUserSettings = GatewayHttpChatCompletionsImagesUserSettings()
}

@jsonable
public struct GatewayHttpResponsesPdfUserSettings {
    public var maxPages: Int64 = 4
    public var maxPixels: Int64 = 4 * 1024 * 1024
    public var minTextChars: Int64 = 200
}

@jsonable
public struct GatewayHttpResponsesFilesUserSettings {
    public var allowUrl: Bool = true
    public var urlAllowlist: Array<String> = []
    public var allowedMimes: Array<String> = []
    public var maxBytes: Int64 = 5 * 1024 * 1024
    public var maxChars: Int64 = 200000
    public var maxRedirects: Int64 = 3
    public var timeoutMs: Int64 = 10000
    public var pdf: GatewayHttpResponsesPdfUserSettings = GatewayHttpResponsesPdfUserSettings()
}

@jsonable
public struct GatewayHttpResponsesImagesUserSettings {
    public var allowUrl: Bool = true
    public var urlAllowlist: Array<String> = []
    public var allowedMimes: Array<String> = []
    public var maxBytes: Int64 = 10 * 1024 * 1024
    public var maxRedirects: Int64 = 3
    public var timeoutMs: Int64 = 10000
}

@jsonable
public struct GatewayHttpResponsesUserSettings {
    public var enabled: Bool = false
    public var maxBodyBytes: Int64 = 20 * 1024 * 1024
    public var maxUrlParts: Int64 = 8
    public var files: GatewayHttpResponsesFilesUserSettings = GatewayHttpResponsesFilesUserSettings()
    public var images: GatewayHttpResponsesImagesUserSettings = GatewayHttpResponsesImagesUserSettings()
}

@jsonable
public struct GatewayHttpEndpointsUserSettings {
    public var chatCompletions: GatewayHttpChatCompletionsUserSettings = GatewayHttpChatCompletionsUserSettings()
    public var responses: GatewayHttpResponsesUserSettings = GatewayHttpResponsesUserSettings()
}

@jsonable
public struct GatewayHttpSecurityHeadersUserSettings {
    public var strictTransportSecurity: String = ""
}

@jsonable
public struct GatewayHttpUserSettings {
    public var endpoints: GatewayHttpEndpointsUserSettings = GatewayHttpEndpointsUserSettings()
    public var securityHeaders: GatewayHttpSecurityHeadersUserSettings = GatewayHttpSecurityHeadersUserSettings()
}

@jsonable
public struct GatewayPushApnsRelayUserSettings {
    public var baseUrl: String = ""
    public var timeoutMs: Int64 = 10000
}

@jsonable
public struct GatewayPushApnsUserSettings {
    public var relay: GatewayPushApnsRelayUserSettings = GatewayPushApnsRelayUserSettings()
}

@jsonable
public struct GatewayPushUserSettings {
    public var apns: GatewayPushApnsUserSettings = GatewayPushApnsUserSettings()
}

@jsonable
public struct GatewayNodesBrowserUserSettings {
    public var mode: String = "auto"
    public var node: String = ""
}

@jsonable
public struct GatewayNodesUserSettings {
    public var browser: GatewayNodesBrowserUserSettings = GatewayNodesBrowserUserSettings()
    public var allowCommands: Array<String> = []
    public var denyCommands: Array<String> = []
}

@jsonable
public struct GatewayWebchatUserSettings {
    public var chatHistoryMaxChars: Int64 = 12000
}

@jsonable
public struct TelegramActionUserSettings {
    public var reactions: Bool = true
    public var sendMessage: Bool = true
    public var poll: Bool = false
    public var deleteMessage: Bool = false
    public var editMessage: Bool = false
    public var pinMessage: Bool = false
    public var unpinMessage: Bool = false
    public var photo: Bool = false
    public var document: Bool = false
    public var audio: Bool = false
    public var voice: Bool = false
    public var video: Bool = false
    public var videoNote: Bool = false
    public var sticker: Bool = false
    public var createForumTopic: Bool = false
    public var editForumTopic: Bool = false
    public var inlineKeyboard: Bool = false
    public var callbackQuery: Bool = false
}

@jsonable
public struct TelegramThreadBindingsUserSettings {
    public var enabled: Bool = false
    public var spawnSubagentSessions: Bool = false
    public var spawnAcpSessions: Bool = false
}

@jsonable
public struct TelegramInlineButtonsUserSettings {
    public var scope: String = "allowlist"
    public var allowlist: Array<String> = []
}

@jsonable
public struct TelegramExecApprovalsUserSettings {
    public var enabled: String = "auto"
    public var approvers: Array<String> = []
    public var agentFilter: Array<String> = []
    public var sessionFilter: Array<String> = []
    public var target: String = "dm"
}

@jsonable
public struct TelegramErrorPolicyUserSettings {
    public var policy: String = "always"
    public var cooldownMs: Int64 = 60000
    public var silentErrorReplies: Bool = false
}

@jsonable
public struct TelegramAutoTopicLabelUserSettings {
    public var enabled: Bool = true
    public var strategy: String = "deterministic"
    public var prompt: String = ""
}

@jsonable
public struct TelegramMediaUserSettings {
    public var downloadEnabled: Bool = true
    public var mediaMaxBytes: Int64 = 20 * 1024 * 1024
    public var allowedMimes: Array<String> = []
    public var outboundAllowUrl: Bool = false
    public var outboundFetchUrl: Bool = false
    public var outboundAllowedUrlDomains: Array<String> = []
    public var outboundAllowedUrlSchemes: Array<String> = ["https"]
    public var outboundAllowLocalPath: Bool = false
    public var outboundLocalRoots: Array<String> = []
    public var trustedLocalFileRoots: Array<String> = []
    public var albumPolicy: String = "single-largest"
    public var warnOnDownloadFailure: Bool = true
}

@jsonable
public struct TelegramNetworkUserSettings {
    public var autoSelectFamily: Bool = true
    public var dnsResultOrder: String = "ipv4first"
    public var dangerouslyAllowPrivateNetwork: Bool = false
    public var insecureSkipTlsVerify: Bool = false
    public var envProxyEnabled: Bool = false
    public var allowedUpdatesExtra: Array<String> = []
    public var getFileRetryCount: Int64 = 3
}

@jsonable
public struct TelegramCustomCommandUserSettings {
    public var command: String = ""
    public var description: String = ""
    public var prompt: String = ""
    public var reply: String = ""
}

@jsonable
public struct TelegramCommandsUserSettings {
    public var useAccessGroups: Bool = false
    public var allowFrom: Array<String> = []
}

@jsonable
public struct TelegramUserSettings {
    public var enabled: Bool = false
    public var defaultAccount: String = "default"
    public var botToken: String = ""
    public var tokenFile: String = ""
    public var dmPolicy: String = "pairing"
    public var allowFrom: Array<String> = []
    public var defaultTo: String = ""
    public var groupPolicy: String = "allowlist"
    public var groupAllowFrom: Array<String> = []
    public var groups: Option<JsonObject> = None
    public var direct: Option<JsonObject> = None
    public var dms: Option<JsonObject> = None
    public var accounts: Option<JsonObject> = None
    public var commandsNative: String = "auto"
    public var commands: TelegramCommandsUserSettings = TelegramCommandsUserSettings()
    public var customCommands: Array<TelegramCustomCommandUserSettings> = []
    public var replyToMode: String = "off"
    public var groupHistoryEnabled: Bool = true
    public var groupHistoryLimit: Int64 = 20
    public var textChunkLimit: Int64 = 4000
    public var chunkMode: String = "length"
    public var streaming: String = "partial"
    public var blockStreaming: Bool = false
    public var timeoutSeconds: Int64 = 30
    public var linkPreview: Bool = true
    public var silent: Bool = false
    public var webhookUrl: String = ""
    public var webhookSecret: String = ""
    public var webhookCertPath: String = ""
    public var webhookPath: String = "/telegram-webhook"
    public var webhookHost: String = "127.0.0.1"
    public var webhookPort: Int64 = 8787
    public var webhookMaxBodyBytes: Int64 = 1024 * 1024
    public var webhookBodyTimeoutMs: Int64 = 30000
    public var webhookRateLimitWindowMs: Int64 = 60000
    public var webhookRateLimitMaxRequests: Int64 = 120
    public var apiRoot: String = "https://api.telegram.org"
    public var proxy: String = ""
    public var reactionNotifications: String = "off"
    public var reactionLevel: String = "ack"
    public var ackReaction: String = "👀"
    public var removeAckAfterReply: Bool = false
    public var configWrites: Bool = true
    public var actions: TelegramActionUserSettings = TelegramActionUserSettings()
    public var inlineButtons: TelegramInlineButtonsUserSettings = TelegramInlineButtonsUserSettings()
    public var execApprovals: TelegramExecApprovalsUserSettings = TelegramExecApprovalsUserSettings()
    public var errorPolicy: TelegramErrorPolicyUserSettings = TelegramErrorPolicyUserSettings()
    public var autoTopicLabel: TelegramAutoTopicLabelUserSettings = TelegramAutoTopicLabelUserSettings()
    public var threadBindings: TelegramThreadBindingsUserSettings = TelegramThreadBindingsUserSettings()
    public var media: TelegramMediaUserSettings = TelegramMediaUserSettings()
    public var image: JsonObject = JsonObject()
    public var video: JsonObject = JsonObject()
    public var videoGeneration: JsonObject = JsonObject()
    public var imageGeneration: JsonObject = JsonObject()
    public var network: TelegramNetworkUserSettings = TelegramNetworkUserSettings()
    public var speech: GatewayChannelSpeechUserSettings = GatewayChannelSpeechUserSettings()
}

/**
 * 用户可编辑的飞书网关配置（持久化在 `~/.metis/metis.json` 的 `gateway.feishu`）。
 * 运行态只读取配置文件，不再使用 `.env` 对这些字段做覆盖。
 */
@jsonable
public struct FeishuMediaUserSettings {
    public var downloadEnabled: Bool = false
    public var mediaMaxBytes: Int64 = 20 * 1024 * 1024
    public var allowedMimes: Array<String> = []
    public var downloadRoot: String = "/tmp/metis-feishu-media"
}

@jsonable
public struct FeishuUserSettings {
    /** 默认 true，与原先未设置 FEISHU_ENABLED 时视为开启的行为对齐；可用 `gateway channel disable feishu` 关闭。 */
    public var enabled: Bool = true
    public var defaultAccount: String = "default"
    public var streaming: String = "partial"
    public var blockStreaming: Bool = false
    public var appId: String = ""
    public var appSecret: String = ""
    public var accounts: Option<JsonObject> = None
    public var receiveMode: String = "long_connect"
    public var domain: String = "https://open.feishu.cn"
    public var botOpenId: String = ""
    public var webhookHost: String = "127.0.0.1"
    public var webhookPort: Int64 = 3000
    public var webhookPath: String = "/feishu/events"
    public var verificationToken: String = ""
    public var encryptKey: String = ""
    public var groupSessionScope: String = "group"
    public var threadSession: Bool = false
    public var groups: Option<JsonObject> = None
    public var groupPolicy: String = "allowlist"
    public var groupAllowFrom: Array<String> = []
    public var requireMention: Bool = true
    public var allowBots: Bool = false
    public var replyInThread: String = "disabled"
    public var requireSignatureHeaders: Bool = true
    public var requestMaxSkewSeconds: Int64 = 300
    public var media: FeishuMediaUserSettings = FeishuMediaUserSettings()
    public var speech: GatewayChannelSpeechUserSettings = GatewayChannelSpeechUserSettings()
    public var image: JsonObject = JsonObject()
    public var video: JsonObject = JsonObject()
    public var videoGeneration: JsonObject = JsonObject()
    public var imageGeneration: JsonObject = JsonObject()
}

/**
 * 用户可编辑的 QQ 网关配置（`gateway.qq`）。
 */
@jsonable
public struct QQUserSettings {
    public var enabled: Bool = false
    public var streaming: String = "partial"
    public var blockStreaming: Bool = false
    /** 目前仅支持 official_ws。 */
    public var mode: String = "official_ws"
    /** 历史保留字段；当前官方 WS 路径不使用本地 webhook 监听。 */
    public var webhookHost: String = "127.0.0.1"
    public var webhookPort: Int64 = 5701
    public var webhookPath: String = "/qq/events"
    public var accessToken: String = ""
    public var requireAuthorizationHeader: Bool = true
    /** 历史保留字段；当前官方 WS 路径不走 OneBot。 */
    public var onebotApiBaseUrl: String = "http://127.0.0.1:5700"
    public var sendApiMode: String = "split"
    public var botQQ: String = ""
    public var dedupWindowSize: Int64 = 2000
    public var appId: String = ""
    public var appSecret: String = ""
    public var officialBotToken: String = ""
    public var officialIntents: Int64 = 33559041
    public var officialTokenUrl: String = ""
    public var officialGatewayUrl: String = ""
    public var officialWebsocketUrl: String = ""
    public var officialAuthScheme: String = ""
    public var officialSendPrivateUrlTemplate: String = ""
    public var officialSendGroupUrlTemplate: String = ""
    public var speech: GatewayChannelSpeechUserSettings = GatewayChannelSpeechUserSettings()
    public var image: JsonObject = JsonObject()
    public var video: JsonObject = JsonObject()
    public var videoGeneration: JsonObject = JsonObject()
    public var imageGeneration: JsonObject = JsonObject()
}

/**
 * 网关会话：私信如何合并/隔离、是否持久化转录。
 *
 * - `per-chat`：与历史行为一致，按 `渠道:direct|group:peerId` 分桶（群聊共享同一上下文）。
 * - `main`：所有渠道的私信共用一条 `gateway:dm:main`（仅适合单用户机器人）。
 * - `per-peer`：按发送者全局分桶（跨渠道同一 sender 共享；群聊为 `gateway:peer:<senderId>`）。
 * - `per-channel-peer`：私信 `渠道:dm:u:<senderId>`；群聊 `渠道:group:<peerId>:u:<senderId>`。
 */
@jsonable
public struct GatewaySessionUserSettings {
    public var dmScope: String = "per-chat"
    public var persistenceEnabled: Bool = true
    /**
     * 持久化根路径为 `~/.metis/agents/<agentId>/sessions/`（转录 `*.jsonl` + `sessions.json` 索引）。
     * 默认 `main`。
     */
    public var agentId: String = "main"
}

/**
 * 网关扩展渠道插件：在源码中注册 `GatewayChannelPlugin` 后，在此打开开关。
 *
 * 插件专属配置建议放在 `gateway.channelsExtra` 下，以 `id` 为键（与 `pluginId()` 一致）。
 */
@jsonable
public struct GatewayPluginUserSettings {
    /** 与 `GatewayChannelPlugin.pluginId()` 一致，例如 `dingtalk`。 */
    public var id: String = ""
    public var enabled: Bool = true
}

/**
 * 网关总配置（`gateway` 根键）。
 *
 * - `channelsExtra`：预留给钉钉等后续渠道；实现新适配器后可在此存放任意 JSON，
 *   并在 `gateway_config_factory` 中解析与注册（见 `metis.gateway.config.channel_registry`）。
 */
@jsonable
public struct GatewayUserSettings {
    public var port: Int64 = 18788
    public var mode: String = "local"
    public var bind: String = "loopback"
    public var customBindHost: String = ""
    public var enabled: Bool = true
    /** 为 false 时网关内 `CronRunner` 不调度、不触发任务。 */
    public var cronEnabled: Bool = true
    /**
     * `gateway:cron:run:*` 单次运行转录保留小时数；<=0 关闭清扫。
     */
    public var cronRunSessionRetentionHours: Int64 = 24
    public var discovery: GatewayDiscoveryUserSettings = GatewayDiscoveryUserSettings()
    public var tls: GatewayTlsUserSettings = GatewayTlsUserSettings()
    public var controlUi: GatewayControlUiUserSettings = GatewayControlUiUserSettings()
    public var auth: GatewayAuthUserSettings = GatewayAuthUserSettings()
    public var tailscale: GatewayTailscaleUserSettings = GatewayTailscaleUserSettings()
    public var remote: GatewayRemoteUserSettings = GatewayRemoteUserSettings()
    public var reload: GatewayReloadUserSettings = GatewayReloadUserSettings()
    public var http: GatewayHttpUserSettings = GatewayHttpUserSettings()
    public var push: GatewayPushUserSettings = GatewayPushUserSettings()
    public var nodes: GatewayNodesUserSettings = GatewayNodesUserSettings()
    public var trustedProxies: Array<String> = []
    public var allowRealIpFallback: Bool = false
    public var session: GatewaySessionUserSettings = GatewaySessionUserSettings()
    public var canvas: GatewayCanvasHostUserSettings = GatewayCanvasHostUserSettings()
    public var talk: GatewayTalkUserSettings = GatewayTalkUserSettings()
    public var speech: GatewaySpeechUserSettings = GatewaySpeechUserSettings()
    public var media: GatewayMediaUserSettings = GatewayMediaUserSettings()
    public var feishu: FeishuUserSettings = FeishuUserSettings()
    public var qq: QQUserSettings = QQUserSettings()
    public var telegram: TelegramUserSettings = TelegramUserSettings()
    /**
     * Optional per-channel primary model binding.
     * Example:
     * {
     *   "feishu": "deepseek:deepseek-chat",
     *   "qq": "qwen:qwen-plus"
     * }
     */
    public var channelModels: HashMap<String, String> = HashMap<String, String>()
    /** 网关 P1 Agent 工具白名单/黑名单。 */
    public var tools: GatewayToolsUserSettings = GatewayToolsUserSettings()
    /** Subagent 启动策略与资源上限。 */
    public var subagents: GatewaySubagentPolicyUserSettings = GatewaySubagentPolicyUserSettings()
    public var webchat: GatewayWebchatUserSettings = GatewayWebchatUserSettings()
    public var channelHealthCheckMinutes: Int64 = 5
    public var channelStaleEventThresholdMinutes: Int64 = 30
    public var channelMaxRestartsPerHour: Int64 = 10
    /**
     * 已注册的扩展渠道插件实例开关（飞书/QQ 仍走 `feishu` / `qq` 强类型字段，不在此列表）。
     */
    public var gatewayPlugins: Array<GatewayPluginUserSettings> = []
    public var channelsExtra: Option<JsonObject> = None
}
