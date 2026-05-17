package metis.gateway.model

import std.collection.HashMap
import stdx.encoding.json.{JsonObject, JsonValue}

/**
 * 单渠道路由策略（P0 最小版）。
 * - allowFrom: 允许的 senderId 列表；包含 "*" 表示放开。
 * - requireMentionInGroup: 群消息是否必须 @ 机器人。
 * - enableDirect/enableGroup: 私聊或群聊是否开启处理。
 */
public class ChannelPolicyConfig {
    public let allowFrom: Array<String>
    public let requireMentionInGroup: Bool
    public let enableDirect: Bool
    public let enableGroup: Bool

    public init(
        allowFrom!: Array<String> = [],
        requireMentionInGroup!: Bool = true,
        enableDirect!: Bool = true,
        enableGroup!: Bool = true
    ) {
        this.allowFrom = allowFrom
        this.requireMentionInGroup = requireMentionInGroup
        this.enableDirect = enableDirect
        this.enableGroup = enableGroup
    }
}

public class GatewayTlsConfig {
    public let enabled: Bool
    public let autoGenerate: Bool
    public let certPath: String
    public let keyPath: String
    public let caPath: String

    public init(
        enabled!: Bool = false,
        autoGenerate!: Bool = true,
        certPath!: String = "",
        keyPath!: String = "",
        caPath!: String = ""
    ) {
        this.enabled = enabled
        this.autoGenerate = autoGenerate
        this.certPath = certPath
        this.keyPath = keyPath
        this.caPath = caPath
    }
}

public class GatewayWideAreaDiscoveryConfig {
    public let enabled: Bool
    public let domain: String

    public init(enabled!: Bool = false, domain!: String = "") {
        this.enabled = enabled
        this.domain = domain
    }
}

public class GatewayMdnsDiscoveryConfig {
    public let mode: String

    public init(mode!: String = "minimal") {
        this.mode = mode
    }
}

public class GatewayDiscoveryConfig {
    public let wideArea: GatewayWideAreaDiscoveryConfig
    public let mdns: GatewayMdnsDiscoveryConfig

    public init(
        wideArea!: GatewayWideAreaDiscoveryConfig = GatewayWideAreaDiscoveryConfig(),
        mdns!: GatewayMdnsDiscoveryConfig = GatewayMdnsDiscoveryConfig()
    ) {
        this.wideArea = wideArea
        this.mdns = mdns
    }
}

public class GatewayCanvasHostConfig {
    public let enabled: Bool
    public let root: String
    public let port: Int64
    public let liveReload: Bool

    public init(
        enabled!: Bool = false,
        root!: String = "",
        port!: Int64 = 18793,
        liveReload!: Bool = true
    ) {
        this.enabled = enabled
        this.root = root
        this.port = port
        this.liveReload = liveReload
    }
}

public class GatewayTalkConfig {
    public let provider: String
    public let providers: Option<JsonObject>
    public let interruptOnSpeech: Bool
    public let silenceTimeoutMs: Int64

    public init(
        provider!: String = "",
        providers!: Option<JsonObject> = None,
        interruptOnSpeech!: Bool = true,
        silenceTimeoutMs!: Int64 = 1200
    ) {
        this.provider = provider
        this.providers = providers
        this.interruptOnSpeech = interruptOnSpeech
        this.silenceTimeoutMs = silenceTimeoutMs
    }
}

public class GatewayControlUiConfig {
    public let enabled: Bool
    public let basePath: String
    public let root: String
    public let allowedOrigins: Array<String>
    public let dangerouslyAllowHostHeaderOriginFallback: Bool
    public let allowInsecureAuth: Bool
    public let dangerouslyDisableDeviceAuth: Bool

    public init(
        enabled!: Bool = true,
        basePath!: String = "",
        root!: String = "",
        allowedOrigins!: Array<String> = [],
        dangerouslyAllowHostHeaderOriginFallback!: Bool = false,
        allowInsecureAuth!: Bool = false,
        dangerouslyDisableDeviceAuth!: Bool = false
    ) {
        this.enabled = enabled
        this.basePath = basePath
        this.root = root
        this.allowedOrigins = allowedOrigins
        this.dangerouslyAllowHostHeaderOriginFallback = dangerouslyAllowHostHeaderOriginFallback
        this.allowInsecureAuth = allowInsecureAuth
        this.dangerouslyDisableDeviceAuth = dangerouslyDisableDeviceAuth
    }
}

public class GatewayTrustedProxyConfig {
    public let userHeader: String
    public let requiredHeaders: Array<String>
    public let allowUsers: Array<String>

    public init(
        userHeader!: String = "",
        requiredHeaders!: Array<String> = [],
        allowUsers!: Array<String> = []
    ) {
        this.userHeader = userHeader
        this.requiredHeaders = requiredHeaders
        this.allowUsers = allowUsers
    }
}

public class GatewayAuthRateLimitConfig {
    public let maxAttempts: Int64
    public let windowMs: Int64
    public let lockoutMs: Int64
    public let exemptLoopback: Bool

    public init(
        maxAttempts!: Int64 = 10,
        windowMs!: Int64 = 60000,
        lockoutMs!: Int64 = 300000,
        exemptLoopback!: Bool = true
    ) {
        this.maxAttempts = maxAttempts
        this.windowMs = windowMs
        this.lockoutMs = lockoutMs
        this.exemptLoopback = exemptLoopback
    }
}

public class GatewayAuthConfig {
    public let mode: String
    public let token: Option<JsonValue>
    public let password: Option<JsonValue>
    public let allowTailscale: Bool
    public let rateLimit: GatewayAuthRateLimitConfig
    public let trustedProxy: GatewayTrustedProxyConfig

    public init(
        mode!: String = "token",
        token!: Option<JsonValue> = None,
        password!: Option<JsonValue> = None,
        allowTailscale!: Bool = false,
        rateLimit!: GatewayAuthRateLimitConfig = GatewayAuthRateLimitConfig(),
        trustedProxy!: GatewayTrustedProxyConfig = GatewayTrustedProxyConfig()
    ) {
        this.mode = mode
        this.token = token
        this.password = password
        this.allowTailscale = allowTailscale
        this.rateLimit = rateLimit
        this.trustedProxy = trustedProxy
    }
}

public class GatewayTailscaleConfig {
    public let mode: String
    public let resetOnExit: Bool

    public init(mode!: String = "off", resetOnExit!: Bool = false) {
        this.mode = mode
        this.resetOnExit = resetOnExit
    }
}

public class GatewayRemoteConfig {
    public let enabled: Bool
    public let url: String
    public let transport: String
    public let token: Option<JsonValue>
    public let password: Option<JsonValue>
    public let tlsFingerprint: String
    public let sshTarget: String
    public let sshIdentity: String

    public init(
        enabled!: Bool = false,
        url!: String = "",
        transport!: String = "ssh",
        token!: Option<JsonValue> = None,
        password!: Option<JsonValue> = None,
        tlsFingerprint!: String = "",
        sshTarget!: String = "",
        sshIdentity!: String = ""
    ) {
        this.enabled = enabled
        this.url = url
        this.transport = transport
        this.token = token
        this.password = password
        this.tlsFingerprint = tlsFingerprint
        this.sshTarget = sshTarget
        this.sshIdentity = sshIdentity
    }
}

public class GatewayReloadConfig {
    public let mode: String
    public let debounceMs: Int64
    public let deferralTimeoutMs: Int64

    public init(
        mode!: String = "hybrid",
        debounceMs!: Int64 = 300,
        deferralTimeoutMs!: Int64 = 300000
    ) {
        this.mode = mode
        this.debounceMs = debounceMs
        this.deferralTimeoutMs = deferralTimeoutMs
    }
}

public class GatewayHttpChatCompletionsImagesConfig {
    public let allowUrl: Bool
    public let urlAllowlist: Array<String>
    public let allowedMimes: Array<String>
    public let maxBytes: Int64
    public let maxRedirects: Int64
    public let timeoutMs: Int64

    public init(
        allowUrl!: Bool = false,
        urlAllowlist!: Array<String> = [],
        allowedMimes!: Array<String> = [],
        maxBytes!: Int64 = 10 * 1024 * 1024,
        maxRedirects!: Int64 = 3,
        timeoutMs!: Int64 = 10000
    ) {
        this.allowUrl = allowUrl
        this.urlAllowlist = urlAllowlist
        this.allowedMimes = allowedMimes
        this.maxBytes = maxBytes
        this.maxRedirects = maxRedirects
        this.timeoutMs = timeoutMs
    }
}

public class GatewayHttpChatCompletionsConfig {
    public let enabled: Bool
    public let maxBodyBytes: Int64
    public let maxImageParts: Int64
    public let maxTotalImageBytes: Int64
    public let images: GatewayHttpChatCompletionsImagesConfig

    public init(
        enabled!: Bool = false,
        maxBodyBytes!: Int64 = 20 * 1024 * 1024,
        maxImageParts!: Int64 = 8,
        maxTotalImageBytes!: Int64 = 20 * 1024 * 1024,
        images!: GatewayHttpChatCompletionsImagesConfig = GatewayHttpChatCompletionsImagesConfig()
    ) {
        this.enabled = enabled
        this.maxBodyBytes = maxBodyBytes
        this.maxImageParts = maxImageParts
        this.maxTotalImageBytes = maxTotalImageBytes
        this.images = images
    }
}

public class GatewayHttpResponsesPdfConfig {
    public let maxPages: Int64
    public let maxPixels: Int64
    public let minTextChars: Int64

    public init(
        maxPages!: Int64 = 4,
        maxPixels!: Int64 = 4 * 1024 * 1024,
        minTextChars!: Int64 = 200
    ) {
        this.maxPages = maxPages
        this.maxPixels = maxPixels
        this.minTextChars = minTextChars
    }
}

public class GatewayHttpResponsesFilesConfig {
    public let allowUrl: Bool
    public let urlAllowlist: Array<String>
    public let allowedMimes: Array<String>
    public let maxBytes: Int64
    public let maxChars: Int64
    public let maxRedirects: Int64
    public let timeoutMs: Int64
    public let pdf: GatewayHttpResponsesPdfConfig

    public init(
        allowUrl!: Bool = true,
        urlAllowlist!: Array<String> = [],
        allowedMimes!: Array<String> = [],
        maxBytes!: Int64 = 5 * 1024 * 1024,
        maxChars!: Int64 = 200000,
        maxRedirects!: Int64 = 3,
        timeoutMs!: Int64 = 10000,
        pdf!: GatewayHttpResponsesPdfConfig = GatewayHttpResponsesPdfConfig()
    ) {
        this.allowUrl = allowUrl
        this.urlAllowlist = urlAllowlist
        this.allowedMimes = allowedMimes
        this.maxBytes = maxBytes
        this.maxChars = maxChars
        this.maxRedirects = maxRedirects
        this.timeoutMs = timeoutMs
        this.pdf = pdf
    }
}

public class GatewayHttpResponsesImagesConfig {
    public let allowUrl: Bool
    public let urlAllowlist: Array<String>
    public let allowedMimes: Array<String>
    public let maxBytes: Int64
    public let maxRedirects: Int64
    public let timeoutMs: Int64

    public init(
        allowUrl!: Bool = true,
        urlAllowlist!: Array<String> = [],
        allowedMimes!: Array<String> = [],
        maxBytes!: Int64 = 10 * 1024 * 1024,
        maxRedirects!: Int64 = 3,
        timeoutMs!: Int64 = 10000
    ) {
        this.allowUrl = allowUrl
        this.urlAllowlist = urlAllowlist
        this.allowedMimes = allowedMimes
        this.maxBytes = maxBytes
        this.maxRedirects = maxRedirects
        this.timeoutMs = timeoutMs
    }
}

public class GatewayHttpResponsesConfig {
    public let enabled: Bool
    public let maxBodyBytes: Int64
    public let maxUrlParts: Int64
    public let files: GatewayHttpResponsesFilesConfig
    public let images: GatewayHttpResponsesImagesConfig

    public init(
        enabled!: Bool = false,
        maxBodyBytes!: Int64 = 20 * 1024 * 1024,
        maxUrlParts!: Int64 = 8,
        files!: GatewayHttpResponsesFilesConfig = GatewayHttpResponsesFilesConfig(),
        images!: GatewayHttpResponsesImagesConfig = GatewayHttpResponsesImagesConfig()
    ) {
        this.enabled = enabled
        this.maxBodyBytes = maxBodyBytes
        this.maxUrlParts = maxUrlParts
        this.files = files
        this.images = images
    }
}

public class GatewayHttpEndpointsConfig {
    public let chatCompletions: GatewayHttpChatCompletionsConfig
    public let responses: GatewayHttpResponsesConfig

    public init(
        chatCompletions!: GatewayHttpChatCompletionsConfig = GatewayHttpChatCompletionsConfig(),
        responses!: GatewayHttpResponsesConfig = GatewayHttpResponsesConfig()
    ) {
        this.chatCompletions = chatCompletions
        this.responses = responses
    }
}

public class GatewayHttpSecurityHeadersConfig {
    public let strictTransportSecurity: Option<JsonValue>

    public init(strictTransportSecurity!: Option<JsonValue> = None) {
        this.strictTransportSecurity = strictTransportSecurity
    }
}

public class GatewayHttpConfig {
    public let endpoints: GatewayHttpEndpointsConfig
    public let securityHeaders: GatewayHttpSecurityHeadersConfig

    public init(
        endpoints!: GatewayHttpEndpointsConfig = GatewayHttpEndpointsConfig(),
        securityHeaders!: GatewayHttpSecurityHeadersConfig = GatewayHttpSecurityHeadersConfig()
    ) {
        this.endpoints = endpoints
        this.securityHeaders = securityHeaders
    }
}

public class GatewayPushApnsRelayConfig {
    public let baseUrl: String
    public let timeoutMs: Int64

    public init(baseUrl!: String = "", timeoutMs!: Int64 = 10000) {
        this.baseUrl = baseUrl
        this.timeoutMs = timeoutMs
    }
}

public class GatewayPushApnsConfig {
    public let relay: GatewayPushApnsRelayConfig

    public init(relay!: GatewayPushApnsRelayConfig = GatewayPushApnsRelayConfig()) {
        this.relay = relay
    }
}

public class GatewayPushConfig {
    public let apns: GatewayPushApnsConfig

    public init(apns!: GatewayPushApnsConfig = GatewayPushApnsConfig()) {
        this.apns = apns
    }
}

public class GatewayNodesBrowserConfig {
    public let mode: String
    public let node: String

    public init(mode!: String = "auto", node!: String = "") {
        this.mode = mode
        this.node = node
    }
}

public class GatewayNodesConfig {
    public let browser: GatewayNodesBrowserConfig
    public let allowCommands: Array<String>
    public let denyCommands: Array<String>

    public init(
        browser!: GatewayNodesBrowserConfig = GatewayNodesBrowserConfig(),
        allowCommands!: Array<String> = [],
        denyCommands!: Array<String> = []
    ) {
        this.browser = browser
        this.allowCommands = allowCommands
        this.denyCommands = denyCommands
    }
}

public class GatewayWebchatConfig {
    public let chatHistoryMaxChars: Int64

    public init(chatHistoryMaxChars!: Int64 = 12000) {
        this.chatHistoryMaxChars = chatHistoryMaxChars
    }
}

public class TelegramActionConfig {
    public let reactions: Bool
    public let sendMessage: Bool
    public let poll: Bool
    public let deleteMessage: Bool
    public let editMessage: Bool
    public let pinMessage: Bool
    public let unpinMessage: Bool
    public let photo: Bool
    public let document: Bool
    public let audio: Bool
    public let voice: Bool
    public let video: Bool
    public let videoNote: Bool
    public let sticker: Bool
    public let createForumTopic: Bool
    public let editForumTopic: Bool
    public let inlineKeyboard: Bool
    public let callbackQuery: Bool

    public init(
        reactions!: Bool = true,
        sendMessage!: Bool = true,
        poll!: Bool = false,
        deleteMessage!: Bool = false,
        editMessage!: Bool = false,
        pinMessage!: Bool = false,
        unpinMessage!: Bool = false,
        photo!: Bool = false,
        document!: Bool = false,
        audio!: Bool = false,
        voice!: Bool = false,
        video!: Bool = false,
        videoNote!: Bool = false,
        sticker!: Bool = false,
        createForumTopic!: Bool = false,
        editForumTopic!: Bool = false,
        inlineKeyboard!: Bool = false,
        callbackQuery!: Bool = false
    ) {
        this.reactions = reactions
        this.sendMessage = sendMessage
        this.poll = poll
        this.deleteMessage = deleteMessage
        this.editMessage = editMessage
        this.pinMessage = pinMessage
        this.unpinMessage = unpinMessage
        this.photo = photo
        this.document = document
        this.audio = audio
        this.voice = voice
        this.video = video
        this.videoNote = videoNote
        this.sticker = sticker
        this.createForumTopic = createForumTopic
        this.editForumTopic = editForumTopic
        this.inlineKeyboard = inlineKeyboard
        this.callbackQuery = callbackQuery
    }
}

public class TelegramThreadBindingsConfig {
    public let enabled: Bool
    public let spawnSubagentSessions: Bool
    public let spawnAcpSessions: Bool

    public init(
        enabled!: Bool = false,
        spawnSubagentSessions!: Bool = false,
        spawnAcpSessions!: Bool = false
    ) {
        this.enabled = enabled
        this.spawnSubagentSessions = spawnSubagentSessions
        this.spawnAcpSessions = spawnAcpSessions
    }
}

public class TelegramInlineButtonsConfig {
    public let scope: String
    public let allowlist: Array<String>

    public init(scope!: String = "allowlist", allowlist!: Array<String> = []) {
        let normalized = scope.trimAscii().toAsciiLower()
        this.scope = if (normalized == "off" || normalized == "dm" || normalized == "group" || normalized == "all" || normalized == "allowlist") {
            normalized
        } else {
            "allowlist"
        }
        this.allowlist = allowlist
    }
}

public class TelegramExecApprovalsConfig {
    public let enabled: String
    public let approvers: Array<String>
    public let agentFilter: Array<String>
    public let sessionFilter: Array<String>
    public let target: String

    public init(
        enabled!: String = "auto",
        approvers!: Array<String> = [],
        agentFilter!: Array<String> = [],
        sessionFilter!: Array<String> = [],
        target!: String = "dm"
    ) {
        let normalizedEnabled = enabled.trimAscii().toAsciiLower()
        this.enabled = if (normalizedEnabled == "true" || normalizedEnabled == "false" || normalizedEnabled == "auto" || normalizedEnabled == "on" || normalizedEnabled == "off") {
            normalizedEnabled
        } else {
            "auto"
        }
        this.approvers = approvers
        this.agentFilter = agentFilter
        this.sessionFilter = sessionFilter
        let normalizedTarget = target.trimAscii().toAsciiLower()
        this.target = if (normalizedTarget == "dm" || normalizedTarget == "channel" || normalizedTarget == "both") {
            normalizedTarget
        } else {
            "dm"
        }
    }
}

public class TelegramErrorPolicyConfig {
    public let policy: String
    public let cooldownMs: Int64
    public let silentErrorReplies: Bool

    public init(
        policy!: String = "always",
        cooldownMs!: Int64 = 60000,
        silentErrorReplies!: Bool = false
    ) {
        let normalized = policy.trimAscii().toAsciiLower()
        this.policy = if (normalized == "always" || normalized == "once" || normalized == "silent") {
            normalized
        } else {
            "always"
        }
        this.cooldownMs = if (cooldownMs <= 0) { 60000 } else { cooldownMs }
        this.silentErrorReplies = silentErrorReplies
    }
}

public class TelegramAutoTopicLabelConfig {
    public let enabled: Bool
    public let strategy: String
    public let prompt: String

    public init(enabled!: Bool = true, strategy!: String = "deterministic", prompt!: String = "") {
        this.enabled = enabled
        let normalized = strategy.trimAscii().toAsciiLower()
        this.strategy = if (normalized == "off" || normalized == "deterministic" || normalized == "model") {
            normalized
        } else {
            "deterministic"
        }
        this.prompt = prompt.trimAscii()
    }
}

public class TelegramMediaConfig {
    public let downloadEnabled: Bool
    public let mediaMaxBytes: Int64
    public let allowedMimes: Array<String>
    public let outboundAllowUrl: Bool
    public let outboundFetchUrl: Bool
    public let outboundAllowedUrlDomains: Array<String>
    public let outboundAllowedUrlSchemes: Array<String>
    public let outboundAllowLocalPath: Bool
    public let outboundLocalRoots: Array<String>
    public let trustedLocalFileRoots: Array<String>
    public let albumPolicy: String
    public let warnOnDownloadFailure: Bool

    public init(
        downloadEnabled!: Bool = true,
        mediaMaxBytes!: Int64 = 20 * 1024 * 1024,
        allowedMimes!: Array<String> = [],
        outboundAllowUrl!: Bool = false,
        outboundFetchUrl!: Bool = false,
        outboundAllowedUrlDomains!: Array<String> = [],
        outboundAllowedUrlSchemes!: Array<String> = ["https"],
        outboundAllowLocalPath!: Bool = false,
        outboundLocalRoots!: Array<String> = [],
        trustedLocalFileRoots!: Array<String> = [],
        albumPolicy!: String = "single-largest",
        warnOnDownloadFailure!: Bool = true
    ) {
        this.downloadEnabled = downloadEnabled
        this.mediaMaxBytes = mediaMaxBytes
        this.allowedMimes = allowedMimes
        this.outboundAllowUrl = outboundAllowUrl
        this.outboundFetchUrl = outboundFetchUrl
        this.outboundAllowedUrlDomains = outboundAllowedUrlDomains
        this.outboundAllowedUrlSchemes = outboundAllowedUrlSchemes
        this.outboundAllowLocalPath = outboundAllowLocalPath
        this.outboundLocalRoots = outboundLocalRoots
        this.trustedLocalFileRoots = trustedLocalFileRoots
        this.albumPolicy = albumPolicy
        this.warnOnDownloadFailure = warnOnDownloadFailure
    }
}

public class TelegramNetworkConfig {
    public let autoSelectFamily: Bool
    public let dnsResultOrder: String
    public let dangerouslyAllowPrivateNetwork: Bool
    public let insecureSkipTlsVerify: Bool
    public let envProxyEnabled: Bool
    public let allowedUpdatesExtra: Array<String>
    public let getFileRetryCount: Int64

    public init(
        autoSelectFamily!: Bool = true,
        dnsResultOrder!: String = "ipv4first",
        dangerouslyAllowPrivateNetwork!: Bool = false,
        insecureSkipTlsVerify!: Bool = false,
        envProxyEnabled!: Bool = false,
        allowedUpdatesExtra!: Array<String> = [],
        getFileRetryCount!: Int64 = 3
    ) {
        this.autoSelectFamily = autoSelectFamily
        this.dnsResultOrder = dnsResultOrder
        this.dangerouslyAllowPrivateNetwork = dangerouslyAllowPrivateNetwork
        this.insecureSkipTlsVerify = insecureSkipTlsVerify
        this.envProxyEnabled = envProxyEnabled
        this.allowedUpdatesExtra = allowedUpdatesExtra
        this.getFileRetryCount = if (getFileRetryCount <= 0) { 1 } else { getFileRetryCount }
    }
}

public class TelegramCustomCommandConfig {
    public let command: String
    public let description: String
    public let prompt: String
    public let reply: String

    public init(command!: String = "", description!: String = "", prompt!: String = "", reply!: String = "") {
        this.command = command
        this.description = description
        this.prompt = prompt
        this.reply = reply
    }
}

public class TelegramConfig {
    public let accountId: String
    public let defaultAccount: String
    public let enabled: Bool
    public let botToken: String
    public let tokenFile: String
    public let dmPolicy: String
    public let allowFrom: Array<String>
    public let defaultTo: String
    public let groupPolicy: String
    public let groupAllowFrom: Array<String>
    public let groups: Option<JsonObject>
    public let direct: Option<JsonObject>
    public let dms: Option<JsonObject>
    public let accounts: Option<JsonObject>
    public let commandsNative: String
    public let customCommands: Array<TelegramCustomCommandConfig>
    public let replyToMode: String
    public let groupHistoryEnabled: Bool
    public let groupHistoryLimit: Int64
    public let textChunkLimit: Int64
    public let chunkMode: String
    public let streaming: String
    public let blockStreaming: Bool
    public let timeoutSeconds: Int64
    public let linkPreview: Bool
    public let silent: Bool
    public let webhookUrl: String
    public let webhookSecret: String
    public let webhookCertPath: String
    public let webhookPath: String
    public let webhookHost: String
    public let webhookPort: UInt16
    public let webhookMaxBodyBytes: Int64
    public let webhookBodyTimeoutMs: Int64
    public let webhookRateLimitWindowMs: Int64
    public let webhookRateLimitMaxRequests: Int64
    public let trustedProxies: Array<String>
    public let allowRealIpFallback: Bool
    public let apiRoot: String
    public let proxy: String
    public let reactionNotifications: String
    public let reactionLevel: String
    public let ackReaction: String
    public let removeAckAfterReply: Bool
    public let configWrites: Bool
    public let actions: TelegramActionConfig
    public let inlineButtons: TelegramInlineButtonsConfig
    public let execApprovals: TelegramExecApprovalsConfig
    public let errorPolicy: TelegramErrorPolicyConfig
    public let autoTopicLabel: TelegramAutoTopicLabelConfig
    public let threadBindings: TelegramThreadBindingsConfig
    public let media: TelegramMediaConfig
    public let network: TelegramNetworkConfig
    public let policy: ChannelPolicyConfig

    public init(
        accountId!: String = "default",
        defaultAccount!: String = "default",
        enabled!: Bool = false,
        botToken!: String = "",
        tokenFile!: String = "",
        dmPolicy!: String = "pairing",
        allowFrom!: Array<String> = [],
        defaultTo!: String = "",
        groupPolicy!: String = "allowlist",
        groupAllowFrom!: Array<String> = [],
        groups!: Option<JsonObject> = None,
        direct!: Option<JsonObject> = None,
        dms!: Option<JsonObject> = None,
        accounts!: Option<JsonObject> = None,
        commandsNative!: String = "auto",
        customCommands!: Array<TelegramCustomCommandConfig> = [],
        replyToMode!: String = "off",
        groupHistoryEnabled!: Bool = true,
        groupHistoryLimit!: Int64 = 20,
        textChunkLimit!: Int64 = 4000,
        chunkMode!: String = "length",
        streaming!: String = "partial",
        blockStreaming!: Bool = false,
        timeoutSeconds!: Int64 = 30,
        linkPreview!: Bool = true,
        silent!: Bool = false,
        webhookUrl!: String = "",
        webhookSecret!: String = "",
        webhookCertPath!: String = "",
        webhookPath!: String = "/telegram-webhook",
        webhookHost!: String = "127.0.0.1",
        webhookPort!: UInt16 = 8787u16,
        webhookMaxBodyBytes!: Int64 = 1024 * 1024,
        webhookBodyTimeoutMs!: Int64 = 30000,
        webhookRateLimitWindowMs!: Int64 = 60000,
        webhookRateLimitMaxRequests!: Int64 = 120,
        trustedProxies!: Array<String> = [],
        allowRealIpFallback!: Bool = false,
        apiRoot!: String = "https://api.telegram.org",
        proxy!: String = "",
        reactionNotifications!: String = "off",
        reactionLevel!: String = "ack",
        ackReaction!: String = "👀",
        removeAckAfterReply!: Bool = false,
        configWrites!: Bool = true,
        actions!: TelegramActionConfig = TelegramActionConfig(),
        inlineButtons!: TelegramInlineButtonsConfig = TelegramInlineButtonsConfig(),
        execApprovals!: TelegramExecApprovalsConfig = TelegramExecApprovalsConfig(),
        errorPolicy!: TelegramErrorPolicyConfig = TelegramErrorPolicyConfig(),
        autoTopicLabel!: TelegramAutoTopicLabelConfig = TelegramAutoTopicLabelConfig(),
        threadBindings!: TelegramThreadBindingsConfig = TelegramThreadBindingsConfig(),
        media!: TelegramMediaConfig = TelegramMediaConfig(),
        network!: TelegramNetworkConfig = TelegramNetworkConfig(),
        policy!: ChannelPolicyConfig = ChannelPolicyConfig()
    ) {
        this.accountId = accountId
        this.defaultAccount = if (defaultAccount.trimAscii().isEmpty()) { "default" } else { defaultAccount.trimAscii() }
        this.enabled = enabled
        this.botToken = botToken
        this.tokenFile = tokenFile
        this.dmPolicy = dmPolicy
        this.allowFrom = allowFrom
        this.defaultTo = defaultTo
        this.groupPolicy = groupPolicy
        this.groupAllowFrom = groupAllowFrom
        this.groups = groups
        this.direct = direct
        this.dms = dms
        this.accounts = accounts
        this.commandsNative = commandsNative
        this.customCommands = customCommands
        this.replyToMode = replyToMode
        this.groupHistoryEnabled = groupHistoryEnabled
        this.groupHistoryLimit = if (groupHistoryLimit <= 0) { 20 } else { groupHistoryLimit }
        this.textChunkLimit = textChunkLimit
        this.chunkMode = chunkMode
        this.streaming = streaming
        this.blockStreaming = blockStreaming
        this.timeoutSeconds = timeoutSeconds
        this.linkPreview = linkPreview
        this.silent = silent
        this.webhookUrl = webhookUrl
        this.webhookSecret = webhookSecret
        this.webhookCertPath = webhookCertPath
        this.webhookPath = webhookPath
        this.webhookHost = webhookHost
        this.webhookPort = webhookPort
        this.webhookMaxBodyBytes = webhookMaxBodyBytes
        this.webhookBodyTimeoutMs = webhookBodyTimeoutMs
        this.webhookRateLimitWindowMs = webhookRateLimitWindowMs
        this.webhookRateLimitMaxRequests = webhookRateLimitMaxRequests
        this.trustedProxies = trustedProxies
        this.allowRealIpFallback = allowRealIpFallback
        this.apiRoot = apiRoot
        this.proxy = proxy
        this.reactionNotifications = reactionNotifications
        this.reactionLevel = reactionLevel
        this.ackReaction = ackReaction
        this.removeAckAfterReply = removeAckAfterReply
        this.configWrites = configWrites
        this.actions = actions
        this.inlineButtons = inlineButtons
        this.execApprovals = execApprovals
        this.errorPolicy = errorPolicy
        this.autoTopicLabel = autoTopicLabel
        this.threadBindings = threadBindings
        this.media = media
        this.network = network
        this.policy = policy
    }
}

/**
 * 渠道账号配置（以飞书为例，P0 只保留最小凭据字段）。
 */
public class FeishuMediaConfig {
    public let downloadEnabled: Bool
    public let mediaMaxBytes: Int64
    public let allowedMimes: Array<String>
    public let downloadRoot: String

    public init(
        downloadEnabled!: Bool = false,
        mediaMaxBytes!: Int64 = 20 * 1024 * 1024,
        allowedMimes!: Array<String> = [],
        downloadRoot!: String = "/tmp/metis-feishu-media"
    ) {
        this.downloadEnabled = downloadEnabled
        this.mediaMaxBytes = mediaMaxBytes
        this.allowedMimes = allowedMimes
        this.downloadRoot = if (downloadRoot.trimAscii().isEmpty()) { "/tmp/metis-feishu-media" } else { downloadRoot.trimAscii() }
    }
}

public class FeishuConfig {
    public let accountId: String
    public let defaultAccount: String
    public let enabled: Bool
    public let streaming: String
    public let blockStreaming: Bool
    public let appId: String
    public let appSecret: String
    public let accounts: Option<JsonObject>
    /**
     * 事件接收方式：`long_connect`（官方长连接 WebSocket，无需配置请求 URL）；
     * `webhook`（HTTP 回调，需公网地址或内网穿透）。
     */
    public let receiveMode: String
    /** 开放平台域名，如 `https://open.feishu.cn` 或国际版 `https://open.larksuite.com`。 */
    public let domain: String
    /** 机器人 open_id，用于群聊中判断是否 @ 到机器人（与路由 requireMentionInGroup 配合）。 */
    public let botOpenId: String
    public let webhookHost: String
    public let webhookPort: UInt16
    public let webhookPath: String
    public let verificationToken: String
    public let encryptKey: String
    public let groupSessionScope: String
    public let threadSession: Bool
    public let dmPolicy: String
    public let allowFrom: Array<String>
    public let groups: Option<JsonObject>
    public let groupPolicy: String
    public let groupAllowFrom: Array<String>
    public let requireMention: Bool
    public let allowBots: Bool
    public let replyInThread: String
    public let requireSignatureHeaders: Bool
    public let requestMaxSkewSeconds: Int64
    public let media: FeishuMediaConfig
    public let policy: ChannelPolicyConfig

    public init(
        accountId!: String = "default",
        defaultAccount!: String = "default",
        enabled!: Bool = false,
        streaming!: String = "partial",
        blockStreaming!: Bool = false,
        appId!: String = "",
        appSecret!: String = "",
        accounts!: Option<JsonObject> = None,
        receiveMode!: String = "long_connect",
        domain!: String = "https://open.feishu.cn",
        botOpenId!: String = "",
        webhookHost!: String = "127.0.0.1",
        webhookPort!: UInt16 = 3000u16,
        webhookPath!: String = "/feishu/events",
        verificationToken!: String = "",
        encryptKey!: String = "",
        groupSessionScope!: String = "group",
        threadSession!: Bool = false,
        dmPolicy!: String = "pairing",
        allowFrom!: Array<String> = [],
        groups!: Option<JsonObject> = None,
        groupPolicy!: String = "allowlist",
        groupAllowFrom!: Array<String> = [],
        requireMention!: Bool = true,
        allowBots!: Bool = false,
        replyInThread!: String = "disabled",
        requireSignatureHeaders!: Bool = true,
        requestMaxSkewSeconds!: Int64 = 300,
        media!: FeishuMediaConfig = FeishuMediaConfig(),
        policy!: ChannelPolicyConfig = ChannelPolicyConfig()
    ) {
        this.accountId = if (accountId.trimAscii().isEmpty()) { "default" } else { accountId.trimAscii() }
        this.defaultAccount = if (defaultAccount.trimAscii().isEmpty()) { this.accountId } else { defaultAccount.trimAscii() }
        this.enabled = enabled
        this.streaming = streaming
        this.blockStreaming = blockStreaming
        this.appId = appId
        this.appSecret = appSecret
        this.accounts = accounts
        this.receiveMode = receiveMode
        this.domain = domain
        this.botOpenId = botOpenId
        this.webhookHost = webhookHost
        this.webhookPort = webhookPort
        this.webhookPath = webhookPath
        this.verificationToken = verificationToken
        this.encryptKey = encryptKey
        this.groupSessionScope = groupSessionScope
        this.threadSession = threadSession
        this.dmPolicy = dmPolicy
        this.allowFrom = allowFrom
        this.groups = groups
        this.groupPolicy = groupPolicy
        this.groupAllowFrom = groupAllowFrom
        this.requireMention = requireMention
        this.allowBots = allowBots
        this.replyInThread = replyInThread
        this.requireSignatureHeaders = requireSignatureHeaders
        this.requestMaxSkewSeconds = requestMaxSkewSeconds
        this.media = media
        this.policy = policy
    }
}

/**
 * QQ 渠道配置。
 *
 * 当前正式路径：
 * - official QQ Bot API
 * - WebSocket gateway
 * - AppId/AppSecret
 */
public class QQConfig {
    public let accountId: String
    public let defaultAccount: String
    public let enabled: Bool
    public let streaming: String
    public let blockStreaming: Bool
    public let mode: String // official_ws
    // Historical compatibility fields. The current built-in QQ runtime only uses official_ws.
    public let webhookHost: String
    public let webhookPort: UInt16
    public let webhookPath: String
    public let accessToken: String
    public let requireAuthorizationHeader: Bool
    public let onebotApiBaseUrl: String
    public let sendApiMode: String
    public let botQQ: String
    public let dedupWindowSize: Int64
    public let appId: String
    public let appSecret: String
    public let accounts: Option<JsonObject>
    public let officialBotToken: String
    public let officialTokenUrl: String
    public let officialGatewayUrl: String
    public let officialWebsocketUrl: String
    public let officialAuthScheme: String
    public let officialIntents: Int64
    public let officialSendPrivateUrlTemplate: String
    public let officialSendGroupUrlTemplate: String
    public let policy: ChannelPolicyConfig

    public init(
        accountId!: String = "default",
        defaultAccount!: String = "default",
        enabled!: Bool = false,
        streaming!: String = "partial",
        blockStreaming!: Bool = false,
        mode!: String = "official_ws", // official_ws
        webhookHost!: String = "127.0.0.1",
        webhookPort!: UInt16 = 5701u16,
        webhookPath!: String = "/qq/events",
        accessToken!: String = "",
        requireAuthorizationHeader!: Bool = true,
        onebotApiBaseUrl!: String = "http://127.0.0.1:5700",
        sendApiMode!: String = "split", // split | unified
        botQQ!: String = "",
        dedupWindowSize!: Int64 = 2000,
        appId!: String = "",
        appSecret!: String = "",
        accounts!: Option<JsonObject> = None,
        officialBotToken!: String = "",
        officialTokenUrl!: String = "https://bots.qq.com/app/getAppAccessToken",
        officialGatewayUrl!: String = "https://api.sgroup.qq.com/gateway",
        officialWebsocketUrl!: String = "",
        officialAuthScheme!: String = "QQBot",
        officialIntents!: Int64 = 1,
        officialSendPrivateUrlTemplate!: String = "https://api.sgroup.qq.com/v2/users/{peer_id}/messages",
        officialSendGroupUrlTemplate!: String = "https://api.sgroup.qq.com/v2/groups/{peer_id}/messages",
        policy!: ChannelPolicyConfig = ChannelPolicyConfig()
    ) {
        this.accountId = accountId
        this.defaultAccount = defaultAccount
        this.enabled = enabled
        this.streaming = streaming
        this.blockStreaming = blockStreaming
        this.mode = mode
        this.webhookHost = webhookHost
        this.webhookPort = webhookPort
        this.webhookPath = webhookPath
        this.accessToken = accessToken
        this.requireAuthorizationHeader = requireAuthorizationHeader
        this.onebotApiBaseUrl = onebotApiBaseUrl
        this.sendApiMode = sendApiMode
        this.botQQ = botQQ
        this.dedupWindowSize = dedupWindowSize
        this.appId = appId
        this.appSecret = appSecret
        this.accounts = accounts
        this.officialBotToken = officialBotToken
        this.officialTokenUrl = officialTokenUrl
        this.officialGatewayUrl = officialGatewayUrl
        this.officialWebsocketUrl = officialWebsocketUrl
        this.officialAuthScheme = officialAuthScheme
        this.officialIntents = officialIntents
        this.officialSendPrivateUrlTemplate = officialSendPrivateUrlTemplate
        this.officialSendGroupUrlTemplate = officialSendGroupUrlTemplate
        this.policy = policy
    }
}

/**
 * 网关配置（P0）。
 * policyByChannel 的 key 使用 channelToString 的值（如 "feishu"、"qq"）。
 */
public class GatewayConfig {
    public let port: Int64
    public let mode: String
    public let bind: String
    public let customBindHost: String
    public let enabled: Bool
    public let discovery: GatewayDiscoveryConfig
    public let tls: GatewayTlsConfig
    public let controlUi: GatewayControlUiConfig
    public let auth: GatewayAuthConfig
    public let tailscale: GatewayTailscaleConfig
    public let remote: GatewayRemoteConfig
    public let reload: GatewayReloadConfig
    public let http: GatewayHttpConfig
    public let push: GatewayPushConfig
    public let nodes: GatewayNodesConfig
    public let trustedProxies: Array<String>
    public let allowRealIpFallback: Bool
    public let policyByChannel: HashMap<String, ChannelPolicyConfig>
    public let canvas: GatewayCanvasHostConfig
    public let talk: GatewayTalkConfig
    public let feishu: FeishuConfig
    public let qq: QQConfig
    public let telegram: TelegramConfig
    public let webchat: GatewayWebchatConfig
    public let channelHealthCheckMinutes: Int64
    public let channelStaleEventThresholdMinutes: Int64
    public let channelMaxRestartsPerHour: Int64

    public init(
        port!: Int64 = 18789,
        mode!: String = "local",
        bind!: String = "loopback",
        customBindHost!: String = "",
        enabled!: Bool = true,
        discovery!: GatewayDiscoveryConfig = GatewayDiscoveryConfig(),
        tls!: GatewayTlsConfig = GatewayTlsConfig(),
        controlUi!: GatewayControlUiConfig = GatewayControlUiConfig(),
        auth!: GatewayAuthConfig = GatewayAuthConfig(),
        tailscale!: GatewayTailscaleConfig = GatewayTailscaleConfig(),
        remote!: GatewayRemoteConfig = GatewayRemoteConfig(),
        reload!: GatewayReloadConfig = GatewayReloadConfig(),
        http!: GatewayHttpConfig = GatewayHttpConfig(),
        push!: GatewayPushConfig = GatewayPushConfig(),
        nodes!: GatewayNodesConfig = GatewayNodesConfig(),
        trustedProxies!: Array<String> = [],
        allowRealIpFallback!: Bool = false,
        policyByChannel!: HashMap<String, ChannelPolicyConfig> = HashMap<String, ChannelPolicyConfig>(),
        canvas!: GatewayCanvasHostConfig = GatewayCanvasHostConfig(),
        talk!: GatewayTalkConfig = GatewayTalkConfig(),
        feishu!: FeishuConfig = FeishuConfig(),
        qq!: QQConfig = QQConfig(),
        telegram!: TelegramConfig = TelegramConfig(),
        webchat!: GatewayWebchatConfig = GatewayWebchatConfig(),
        channelHealthCheckMinutes!: Int64 = 5,
        channelStaleEventThresholdMinutes!: Int64 = 30,
        channelMaxRestartsPerHour!: Int64 = 10
    ) {
        this.port = port
        this.mode = mode
        this.bind = bind
        this.customBindHost = customBindHost
        this.enabled = enabled
        this.discovery = discovery
        this.tls = tls
        this.controlUi = controlUi
        this.auth = auth
        this.tailscale = tailscale
        this.remote = remote
        this.reload = reload
        this.http = http
        this.push = push
        this.nodes = nodes
        this.trustedProxies = trustedProxies
        this.allowRealIpFallback = allowRealIpFallback
        this.policyByChannel = policyByChannel
        this.canvas = canvas
        this.talk = talk
        this.feishu = feishu
        this.qq = qq
        this.telegram = telegram
        this.webchat = webchat
        this.channelHealthCheckMinutes = channelHealthCheckMinutes
        this.channelStaleEventThresholdMinutes = channelStaleEventThresholdMinutes
        this.channelMaxRestartsPerHour = channelMaxRestartsPerHour
    }
}
