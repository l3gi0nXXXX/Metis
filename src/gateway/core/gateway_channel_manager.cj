package metis.gateway.core

import metis.gateway.model.*
import magic.jsonable.*
import magic.log.LogUtils

import std.collection.{ArrayList, HashMap}
import std.convert.Parsable
import std.sync.Mutex
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonObject}

private class GatewayChannelLiveAccountState {
    public let channelId: String
    public let accountId: String
    public var configured: Bool
    public var running: Bool
    public var connected: Bool
    public var lastInboundAt: Int64
    public var lastError: String

    public init(channelId: String, accountId: String, configured: Bool) {
        this.channelId = channelId.trimAscii().toAsciiLower()
        this.accountId = accountId.trimAscii()
        this.configured = configured
        this.running = false
        this.connected = false
        this.lastInboundAt = 0
        this.lastError = ""
    }
}

public class GatewayRegisteredAdapter {
    public let adapter: ChannelAdapter
    public let channelId: String
    public let accountId: String
    public let pluginId: String
    public let origin: String
    public let runtimeKind: String
    public let compatibilityMode: String
    public let label: String
    public let detailLabel: String
    public let enabled: Bool
    public let configured: Bool
    public let healthMonitorEnabled: Bool

    public init(
        adapter: ChannelAdapter,
        channelId!: String = "",
        accountId!: String = "default",
        pluginId!: String = "",
        origin!: String = "builtin",
        runtimeKind!: String = "adapter",
        compatibilityMode!: String = "native-cangjie",
        label!: String = "",
        detailLabel!: String = "",
        enabled!: Bool = true,
        configured!: Bool = true,
        healthMonitorEnabled!: Bool = true
    ) {
        this.adapter = adapter
        this.channelId = if (channelId.trimAscii().isEmpty()) { adapter.name.trimAscii().toAsciiLower() } else { channelId.trimAscii().toAsciiLower() }
        this.accountId = accountId.trimAscii()
        this.pluginId = pluginId.trimAscii().toAsciiLower()
        this.origin = origin.trimAscii()
        this.runtimeKind = runtimeKind.trimAscii()
        this.compatibilityMode = compatibilityMode.trimAscii()
        this.label = label.trimAscii()
        this.detailLabel = detailLabel.trimAscii()
        this.enabled = enabled
        this.configured = configured
        this.healthMonitorEnabled = healthMonitorEnabled
    }
}

public class GatewayChannelSendResult {
    public let delivered: Bool
    public let lastReason: String
    public let messageId: String

    public init(delivered: Bool, lastReason!: String = "", messageId!: String = "") {
        this.delivered = delivered
        this.lastReason = lastReason.trimAscii()
        this.messageId = messageId.trimAscii()
    }
}

/**
 * 独立的 channel runtime manager，统一承接 adapter 的生命周期与 runtime 状态推进。
 * GatewayService 自身只保留路由和 Agent 桥接职责。
 */
public class GatewayChannelManager {
    private let adapters = ArrayList<GatewayRegisteredAdapter>()
    private let adapterByName = HashMap<String, ChannelAdapter>()
    private let liveStateLock = Mutex()
    private let liveAccounts = HashMap<String, GatewayChannelLiveAccountState>()
    private var started = false

    public init() {}

    private func timingNowMs(): Int64 {
        DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000
    }

    private func timingLog(step: String, startMs: Int64, channelId!: String = "", accountId!: String = ""): Unit {
        let elapsedMs = this.timingNowMs() - startMs
        let channelPart = if (channelId.trimAscii().isEmpty()) { "" } else { " channel=${channelId}" }
        let accountPart = if (accountId.trimAscii().isEmpty()) { "" } else { " account=${accountId}" }
        LogUtils.info("Gateway.channel.timing: step=${step}${channelPart}${accountPart} elapsedMs=${elapsedMs}")
        let scope = if (channelId.trimAscii().isEmpty()) {
            "channel:${step}"
        } else {
            "channel:${channelId}:${step}"
        }
        gatewayLogProcessMemory(scope, note: "account=${accountId.trimAscii()}, elapsedMs=${elapsedMs}")
    }

    private func liveKey(channelId: String, accountId: String): String {
        "${channelId.trimAscii().toAsciiLower()}:${accountId.trimAscii()}"
    }

    private func liveNowMs(): Int64 {
        DateTime.now().toUnixTimeStamp().toMilliseconds()
    }

    private func ensureLiveAccount(entry: GatewayRegisteredAdapter): Unit {
        synchronized(this.liveStateLock) {
            let key = this.liveKey(entry.channelId, entry.accountId)
            match (this.liveAccounts.get(key)) {
                case Some(existing) =>
                    existing.configured = entry.configured
                case None =>
                    this.liveAccounts[key] = GatewayChannelLiveAccountState(
                        entry.channelId,
                        entry.accountId,
                        entry.configured
                    )
            }
        }
    }

    private func updateLiveAccount(
        channelId: String,
        accountId: String,
        updater: (GatewayChannelLiveAccountState) -> Unit
    ): Unit {
        let normalizedChannel = channelId.trimAscii().toAsciiLower()
        let normalizedAccount = accountId.trimAscii()
        synchronized(this.liveStateLock) {
            let key = this.liveKey(normalizedChannel, normalizedAccount)
            let state = match (this.liveAccounts.get(key)) {
                case Some(existing) => existing
                case None =>
                    let created = GatewayChannelLiveAccountState(normalizedChannel, normalizedAccount, false)
                    this.liveAccounts[key] = created
                    created
            }
            updater(state)
        }
    }

    private func cloneLiveAccount(state: GatewayChannelLiveAccountState): JsonObject {
        let row = JsonObject()
        row.put("accountId", state.accountId.toJsonValue())
        row.put("configured", state.configured.toJsonValue())
        row.put("running", state.running.toJsonValue())
        row.put("connected", state.connected.toJsonValue())
        row.put("lastInboundAt", state.lastInboundAt.toJsonValue())
        row.put("lastError", state.lastError.toJsonValue())
        row
    }

    private func channelStatusFromAccounts(accounts: JsonArray): JsonObject {
        let out = JsonObject()
        var configured = false
        var running = false
        var connected = false
        var lastInboundAt: Int64 = 0
        var lastError = ""
        for (item in accounts.getItems()) {
            let row = try { item.asObject() } catch (_e: Exception) { JsonObject() }
            match (row.get("configured")) {
                case Some(v) =>
                    try { if (v.asBool().getValue()) { configured = true } } catch (_e: Exception) { () }
                case None => ()
            }
            match (row.get("running")) {
                case Some(v) =>
                    try { if (v.asBool().getValue()) { running = true } } catch (_e: Exception) { () }
                case None => ()
            }
            match (row.get("connected")) {
                case Some(v) =>
                    try { if (v.asBool().getValue()) { connected = true } } catch (_e: Exception) { () }
                case None => ()
            }
            match (row.get("lastInboundAt")) {
                case Some(v) =>
                    try {
                        let inbound = Int64.parse(v.toJsonString())
                        if (inbound > lastInboundAt) {
                            lastInboundAt = inbound
                        }
                    } catch (_e: Exception) { () }
                case None => ()
            }
            match (row.get("lastError")) {
                case Some(v) =>
                    try {
                        let err = v.asString().getValue().trimAscii()
                        if (lastError.isEmpty() && !err.isEmpty()) {
                            lastError = err
                        }
                    } catch (_e: Exception) { () }
                case None => ()
            }
        }
        out.put("configured", configured.toJsonValue())
        out.put("running", running.toJsonValue())
        out.put("connected", connected.toJsonValue())
        out.put("lastError", lastError.toJsonValue())
        if (lastInboundAt > 0) {
            out.put("lastInboundAt", lastInboundAt.toJsonValue())
        }
        out
    }

    public func liveSnapshotJson(): JsonObject {
        synchronized(this.liveStateLock) {
            let channelAccounts = JsonObject()
            let channelDefaultAccountId = JsonObject()
            let channels = JsonObject()
            for (entry in this.adapters) {
                let channelId = entry.channelId
                let accountId = entry.accountId
                let key = this.liveKey(channelId, accountId)
                let state = match (this.liveAccounts.get(key)) {
                    case Some(existing) => existing
                    case None => GatewayChannelLiveAccountState(channelId, accountId, entry.configured)
                }
                let accounts = try {
                    (channelAccounts.get(channelId) ?? JsonArray([])).asArray()
                } catch (_e: Exception) {
                    JsonArray([])
                }
                accounts.add(this.cloneLiveAccount(state))
                channelAccounts.put(channelId, accounts)
                match (channelDefaultAccountId.get(channelId)) {
                    case Some(_) => ()
                    case None => channelDefaultAccountId.put(channelId, accountId.toJsonValue())
                }
            }
            for (entry in this.adapters) {
                let channelId = entry.channelId
                match (channels.get(channelId)) {
                    case Some(_) => continue
                    case None => ()
                }
                let accounts = try {
                    (channelAccounts.get(channelId) ?? JsonArray([])).asArray()
                } catch (_e: Exception) {
                    JsonArray([])
                }
                channels.put(channelId, this.channelStatusFromAccounts(accounts))
            }
            let result = JsonObject()
            result.put("channelAccounts", channelAccounts)
            result.put("channelDefaultAccountId", channelDefaultAccountId)
            result.put("channels", channels)
            result
        }
    }

    public func registerAdapter(
        adapter: ChannelAdapter,
        channelId!: String = "",
        accountId!: String = "default",
        pluginId!: String = "",
        origin!: String = "builtin",
        runtimeKind!: String = "adapter",
        compatibilityMode!: String = "native-cangjie",
        label!: String = "",
        detailLabel!: String = "",
        enabled!: Bool = true,
        configured!: Bool = true,
        healthMonitorEnabled!: Bool = true
    ): Unit {
        let registered = GatewayRegisteredAdapter(
            adapter,
            channelId: channelId,
            accountId: accountId,
            pluginId: pluginId,
            origin: origin,
            runtimeKind: runtimeKind,
            compatibilityMode: compatibilityMode,
            label: label,
            detailLabel: detailLabel,
            enabled: enabled,
            configured: configured,
            healthMonitorEnabled: healthMonitorEnabled
        )
        this.adapters.add(registered)
        this.adapterByName[adapter.name] = adapter
        this.ensureLiveAccount(registered)
        gatewayChannelRuntimeRegisterAccount(
            registered.channelId,
            accountId: registered.accountId,
            pluginId: registered.pluginId,
            label: registered.label,
            detailLabel: registered.detailLabel,
            origin: registered.origin,
            runtimeKind: registered.runtimeKind,
            compatibilityMode: registered.compatibilityMode,
            enabled: registered.enabled,
            configured: registered.configured,
            healthMonitorEnabled: registered.healthMonitorEnabled
        )
        let _ = gatewayChannelRuntimeMarkMonitorEnabled(
            registered.channelId,
            accountId: registered.accountId,
            enabled: registered.healthMonitorEnabled
        )
    }

    public func getAdapter(name: String): Option<ChannelAdapter> {
        this.adapterByName.get(name)
    }

    public func startChannels(): Unit {
        if (this.started) {
            return
        }
        let startMs = this.timingNowMs()
        for (entry in this.adapters) {
            let entryStartMs = this.timingNowMs()
            if (!gatewayChannelRuntimeCanStart(entry.channelId, accountId: entry.accountId)) {
                this.timingLog("skip-cannot-start", entryStartMs, channelId: entry.channelId, accountId: entry.accountId)
                continue
            }
            this.timingLog("can-start-checked", entryStartMs, channelId: entry.channelId, accountId: entry.accountId)
            gatewayChannelRuntimeMarkStarting(entry.channelId, accountId: entry.accountId)
            this.timingLog("marked-starting", entryStartMs, channelId: entry.channelId, accountId: entry.accountId)
            let adapterStartMs = this.timingNowMs()
            try {
                entry.adapter.start()
                this.timingLog("adapter-started", adapterStartMs, channelId: entry.channelId, accountId: entry.accountId)
                this.updateLiveAccount(entry.channelId, entry.accountId, { state =>
                    state.configured = entry.configured
                    state.running = true
                    state.connected = true
                    state.lastError = ""
                })
                this.timingLog("live-updated-running", entryStartMs, channelId: entry.channelId, accountId: entry.accountId)
                gatewayChannelRuntimeMarkRunning(entry.channelId, accountId: entry.accountId)
                this.timingLog("start", adapterStartMs, channelId: entry.channelId, accountId: entry.accountId)
                this.timingLog("entry-total", entryStartMs, channelId: entry.channelId, accountId: entry.accountId)
            } catch (e: Exception) {
                this.updateLiveAccount(entry.channelId, entry.accountId, { state =>
                    state.configured = entry.configured
                    state.running = false
                    state.connected = false
                    state.lastError = e.message.trimAscii()
                })
                gatewayChannelRuntimeMarkFailure(entry.channelId, accountId: entry.accountId, lifecycleState: "failed", error: e.message)
                LogUtils.error("Gateway.channel.start failed: channel=${entry.channelId} account=${entry.accountId} err=${e.message}")
                this.timingLog("start-failed", adapterStartMs, channelId: entry.channelId, accountId: entry.accountId)
                this.timingLog("entry-total-failed", entryStartMs, channelId: entry.channelId, accountId: entry.accountId)
            }
        }
        this.started = true
        this.timingLog("startChannels-total", startMs)
    }

    public func stopChannels(reason!: String = "manual-stop", manualStop!: Bool = true): Unit {
        if (!this.started) {
            return
        }
        for (entry in this.adapters) {
            try {
                entry.adapter.stop()
                this.updateLiveAccount(entry.channelId, entry.accountId, { state =>
                    state.running = false
                    state.connected = false
                    state.lastError = if (manualStop) { "" } else { reason.trimAscii() }
                })
                gatewayChannelRuntimeMarkStopped(entry.channelId, accountId: entry.accountId, reason: reason, manualStop: manualStop)
            } catch (e: Exception) {
                this.updateLiveAccount(entry.channelId, entry.accountId, { state =>
                    state.running = false
                    state.connected = false
                    state.lastError = e.message.trimAscii()
                })
                gatewayChannelRuntimeMarkFailure(entry.channelId, accountId: entry.accountId, lifecycleState: "failed", error: e.message)
                LogUtils.error("Gateway.channel.stop failed: channel=${entry.channelId} account=${entry.accountId} err=${e.message}")
            }
        }
        this.started = false
    }

    public func processOnce(handleInbound: (InboundMessage, String) -> Unit): Unit {
        if (!this.started) {
            return
        }
        for (entry in this.adapters) {
            let _ = gatewayChannelRuntimeMarkMonitorTick(entry.channelId, accountId: entry.accountId)
            try {
                let messages = entry.adapter.pullInbound()
                if (messages.size > 0) {
                    let now = this.liveNowMs()
                    this.updateLiveAccount(entry.channelId, entry.accountId, { state =>
                        state.running = true
                        state.connected = true
                        state.lastInboundAt = now
                        state.lastError = ""
                    })
                }
                gatewayChannelRuntimeMarkPull(entry.channelId, accountId: entry.accountId, inboundCount: Int64(messages.size))
                for (message in messages) {
                    try {
                        handleInbound(message, entry.accountId)
                    } catch (e: Exception) {
                        this.updateLiveAccount(entry.channelId, entry.accountId, { state =>
                            state.lastError = e.message.trimAscii()
                        })
                        gatewayChannelRuntimeMarkFailure(entry.channelId, accountId: entry.accountId, lifecycleState: "failed", error: e.message)
                        LogUtils.error(
                            "Gateway.handleInbound failed: channel=${channelToString(message.channel)} peer=${message.peerId} err=${e.message}"
                        )
                    }
                }
            } catch (e: Exception) {
                this.updateLiveAccount(entry.channelId, entry.accountId, { state =>
                    state.running = false
                    state.connected = false
                    state.lastError = e.message.trimAscii()
                })
                gatewayChannelRuntimeMarkFailure(entry.channelId, accountId: entry.accountId, lifecycleState: "backoff", error: e.message, backoffMs: 1000)
                LogUtils.error("Gateway.channel.pull failed: channel=${entry.channelId} account=${entry.accountId} err=${e.message}")
            }
        }
    }

    public func sendToAdapterName(adapterName: String, outbound: OutboundMessage): GatewayChannelSendResult {
        let normalized = adapterName.trimAscii()
        let requiredAccountId = outbound.accountId.trimAscii()
        var lastReason: String = ""
        for (entry in this.adapters) {
            if (entry.adapter.name != normalized) {
                continue
            }
            if (!requiredAccountId.isEmpty() && entry.accountId != requiredAccountId) {
                continue
            }
            let sendResult = entry.adapter.send(outbound)
            match (sendResult) {
                case SendResult.Success =>
                    this.updateLiveAccount(entry.channelId, entry.accountId, { state =>
                        state.running = true
                        state.connected = true
                        state.lastError = ""
                    })
                    gatewayChannelRuntimeMarkSend(entry.channelId, accountId: entry.accountId, success: true)
                    return GatewayChannelSendResult(true)
                case SendResult.Failed(reason) =>
                    this.updateLiveAccount(entry.channelId, entry.accountId, { state =>
                        state.lastError = reason.trimAscii()
                    })
                    gatewayChannelRuntimeMarkSend(entry.channelId, accountId: entry.accountId, success: false, detail: reason)
                    lastReason = reason
            }
        }
        let fallbackReason = if (requiredAccountId.isEmpty()) { "adapter not found" } else { "adapter not found for accountId=${requiredAccountId}" }
        GatewayChannelSendResult(false, lastReason: if (lastReason.isEmpty()) { fallbackReason } else { lastReason })
    }
}
