package metis.gateway.core

import metis.gateway.model.*
import magic.jsonable.*
import magic.config.Config
import magic.log.LogUtils

import std.collection.{ArrayList, HashMap}
import std.convert.Parsable
import std.sync.Mutex
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

public func gatewayCanonicalChannelAccountId(channelId: String, rawAccountId: String): String {
    let channel = channelId.trimAscii().toAsciiLower()
    let raw = rawAccountId.trimAscii()
    if (raw.isEmpty() || raw == "default") {
        return "default"
    }
    let lower = raw.toAsciiLower()
    let prefix = "${channel}:"
    if (!channel.isEmpty() && lower.startsWith(prefix)) {
        let suffix = raw[prefix.size..].trimAscii()
        return if (suffix.isEmpty()) { "default" } else { suffix }
    }
    raw
}

public func gatewayChannelAccountIdsEquivalent(channelId: String, left: String, right: String): Bool {
    gatewayCanonicalChannelAccountId(channelId, left) == gatewayCanonicalChannelAccountId(channelId, right)
}

public func gatewaySanitizeChannelDiagnostic(raw: String): String {
    var detail = raw.trimAscii().replace("\n", " ").replace("\r", " ").replace("\t", " ")
    if (detail.size > 240) {
        detail = detail[0..240] + "..."
    }
    let lower = detail.toAsciiLower()
    if (
        lower.contains("authorization") ||
        lower.contains("bearer ") ||
        lower.contains("api_key") ||
        lower.contains("apikey") ||
        lower.contains("api key") ||
        lower.contains("access_token") ||
        lower.contains("bot token") ||
        lower.contains("password")
    ) {
        return "[redacted sensitive error]"
    }
    detail
}

public func gatewayLogEventValue(raw: String): String {
    var detail = gatewaySanitizeChannelDiagnostic(raw)
    if (detail.size > 160) {
        detail = detail[0..160] + "..."
    }
    "\"" + detail.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
}

public func gatewayLogIdentityHash(raw: String): String {
    let detail = raw.trimAscii()
    if (detail.isEmpty()) {
        return "redacted-len-0"
    }
    "redacted-len-${detail.size}"
}

public func gatewayLogEventLine(subsystem: String, event: String, summary: String, fields!: String = ""): String {
    let tail = fields.trimAscii()
    if (tail.isEmpty()) {
        return "Gateway.event subsystem=${subsystem} event=${event} message=${gatewayLogEventValue(summary)}"
    }
    "Gateway.event subsystem=${subsystem} event=${event} message=${gatewayLogEventValue(summary)} ${tail}"
}

public func gatewayLogEventInfo(subsystem: String, event: String, summary: String, fields!: String = ""): Unit {
    LogUtils.info(gatewayLogEventLine(subsystem, event, summary, fields: fields))
}

public func gatewayLogEventDebug(subsystem: String, event: String, summary: String, fields!: String = ""): Unit {
    LogUtils.debug(gatewayLogEventLine(subsystem, event, summary, fields: fields))
}

public func gatewayLogEventError(subsystem: String, event: String, summary: String, fields!: String = ""): Unit {
    LogUtils.error(gatewayLogEventLine(subsystem, event, summary, fields: fields))
}

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
    public let rawAccountId: String
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
        this.rawAccountId = accountId.trimAscii()
        this.accountId = gatewayCanonicalChannelAccountId(this.channelId, accountId)
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
    public let reasonKind: String
    public let rawAccountId: String
    public let canonicalAccountId: String

    public init(
        delivered: Bool,
        lastReason!: String = "",
        messageId!: String = "",
        reasonKind!: String = "",
        rawAccountId!: String = "",
        canonicalAccountId!: String = ""
    ) {
        this.delivered = delivered
        this.lastReason = lastReason.trimAscii()
        this.messageId = messageId.trimAscii()
        this.reasonKind = reasonKind.trimAscii()
        this.rawAccountId = rawAccountId.trimAscii()
        this.canonicalAccountId = canonicalAccountId.trimAscii()
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
        gatewayLogEventDebug(
            "gateway/channel",
            "channel.timing",
            "channel timing",
            fields: "phase=${step}${channelPart}${accountPart} durationMs=${elapsedMs}"
        )
        let scope = if (channelId.trimAscii().isEmpty()) {
            "channel:${step}"
        } else {
            "channel:${channelId}:${step}"
        }
        if (Config.logLevel == "debug" || Config.logLevel == "trace") {
            gatewayLogProcessMemory(scope, note: "account=${accountId.trimAscii()}, elapsedMs=${elapsedMs}")
        }
    }

    private func liveKey(channelId: String, accountId: String): String {
        "${channelId.trimAscii().toAsciiLower()}:${accountId.trimAscii()}"
    }

    private func liveNowMs(): Int64 {
        DateTime.now().toUnixTimeStamp().toMilliseconds()
    }

    private func channelLifecycleBase(action: String, channelId: String, accountId: String): JsonObject {
        let normalizedChannel = channelId.trimAscii().toAsciiLower()
        let canonicalAccount = if (accountId.trimAscii().isEmpty()) {
            ""
        } else {
            gatewayCanonicalChannelAccountId(normalizedChannel, accountId)
        }
        let result = JsonObject()
        result.put("ok", false.toJsonValue())
        result.put("supported", true.toJsonValue())
        result.put("action", JsonString(action))
        result.put("channelId", JsonString(normalizedChannel))
        result.put("channel", JsonString(normalizedChannel))
        result.put("accountId", JsonString(canonicalAccount))
        result.put("runtimeKind", JsonString("native-cangjie"))
        result.put("compatibilityMode", JsonString("native-cangjie"))
        result.put("accounts", JsonArray([]))
        result
    }

    private func channelLifecycleAccounts(result: JsonObject): JsonArray {
        match (result.get("accounts")) {
            case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
    }

    private func matchingEntries(channelId: String, accountId: String): Array<GatewayRegisteredAdapter> {
        let normalizedChannel = channelId.trimAscii().toAsciiLower()
        let canonicalAccount = if (accountId.trimAscii().isEmpty()) {
            ""
        } else {
            gatewayCanonicalChannelAccountId(normalizedChannel, accountId)
        }
        let matches = ArrayList<GatewayRegisteredAdapter>()
        for (entry in this.adapters) {
            if (entry.channelId != normalizedChannel) {
                continue
            }
            if (!canonicalAccount.isEmpty() && entry.accountId != canonicalAccount) {
                continue
            }
            matches.add(entry)
        }
        matches.toArray()
    }

    private func liveAccountRunning(channelId: String, accountId: String): Bool {
        synchronized(this.liveStateLock) {
            let key = this.liveKey(channelId, accountId)
            match (this.liveAccounts.get(key)) {
                case Some(state) => state.running
                case None => false
            }
        }
    }

    private func lifecycleAccountRow(entry: GatewayRegisteredAdapter, ok: Bool, result: String, reason: String, runtime: JsonObject): JsonObject {
        let row = JsonObject()
        row.put("channelId", JsonString(entry.channelId))
        row.put("accountId", JsonString(entry.accountId))
        row.put("ok", ok.toJsonValue())
        row.put("result", JsonString(result))
        row.put("reason", JsonString(reason))
        row.put("runtimeKind", JsonString(entry.runtimeKind))
        row.put("compatibilityMode", JsonString(entry.compatibilityMode))
        row.put("runtime", runtime)
        row
    }

    private func lifecycleMissingResult(action: String, channelId: String, accountId: String): JsonObject {
        let result = this.channelLifecycleBase(action, channelId, accountId)
        result.put("reason", JsonString(if (accountId.trimAscii().isEmpty()) { "channel-not-registered" } else { "account-not-registered" }))
        result.put("result", JsonString("not-started"))
        result.put("manager", gatewayChannelManagerSummary(channelId))
        result
    }

    private func startRegisteredEntry(entry: GatewayRegisteredAdapter, respectRuntimeGuard: Bool): JsonObject {
        if (!entry.enabled) {
            this.updateLiveAccount(entry.channelId, entry.accountId, { state =>
                state.configured = entry.configured
                state.running = false
                state.connected = false
                state.lastError = "disabled"
            })
            let runtime = gatewayChannelRuntimeMarkStopped(entry.channelId, accountId: entry.accountId, reason: "disabled", manualStop: false)
            return this.lifecycleAccountRow(entry, false, "skipped", "disabled", runtime)
        }
        if (!entry.configured) {
            this.updateLiveAccount(entry.channelId, entry.accountId, { state =>
                state.configured = false
                state.running = false
                state.connected = false
                state.lastError = "account-not-configured"
            })
            let runtime = gatewayChannelRuntimeMarkFailure(entry.channelId, accountId: entry.accountId, lifecycleState: "failed", error: "account-not-configured")
            return this.lifecycleAccountRow(entry, false, "not-started", "account-not-configured", runtime)
        }
        if (this.liveAccountRunning(entry.channelId, entry.accountId)) {
            let runtime = gatewayChannelRuntimeMarkRunning(entry.channelId, accountId: entry.accountId)
            return this.lifecycleAccountRow(entry, true, "already-running", "", runtime)
        }
        if (respectRuntimeGuard && !gatewayChannelRuntimeCanStart(entry.channelId, accountId: entry.accountId)) {
            let runtime = gatewayChannelRuntimeAccountsJson(entry.channelId)
            let row = JsonObject()
            row.put("accounts", runtime)
            gatewayLogEventInfo(
                "gateway/channel/${entry.channelId}",
                "channel.starting",
                "channel account start skipped",
                fields: "channel=${entry.channelId} accountId=${entry.accountId} phase=start status=skipped reason=runtime-start-suppressed"
            )
            return this.lifecycleAccountRow(entry, false, "skipped", "runtime-start-suppressed", row)
        }
        gatewayLogEventInfo(
            "gateway/channel/${entry.channelId}",
            "channel.starting",
            "channel account starting",
            fields: "channel=${entry.channelId} accountId=${entry.accountId} phase=start status=starting"
        )
        gatewayChannelRuntimeMarkStarting(entry.channelId, accountId: entry.accountId)
        try {
            entry.adapter.start()
            this.updateLiveAccount(entry.channelId, entry.accountId, { state =>
                state.configured = entry.configured
                state.running = true
                state.connected = true
                state.lastError = ""
            })
            let runtime = gatewayChannelRuntimeMarkRunning(entry.channelId, accountId: entry.accountId)
            gatewayLogEventInfo(
                "gateway/channel/${entry.channelId}",
                "channel.started",
                "channel account running",
                fields: "channel=${entry.channelId} accountId=${entry.accountId} phase=start status=ok"
            )
            return this.lifecycleAccountRow(entry, true, "started", "", runtime)
        } catch (e: Exception) {
            let reason = gatewaySanitizeChannelDiagnostic(e.message)
            this.updateLiveAccount(entry.channelId, entry.accountId, { state =>
                state.configured = entry.configured
                state.running = false
                state.connected = false
                state.lastError = reason
            })
            let runtime = gatewayChannelRuntimeMarkFailure(entry.channelId, accountId: entry.accountId, lifecycleState: "failed", error: reason)
            gatewayLogEventError(
                "gateway/channel/${entry.channelId}",
                "channel.failed",
                "channel account start failed",
                fields: "channel=${entry.channelId} accountId=${entry.accountId} phase=start status=failed errorKind=start_failed error=${gatewayLogEventValue(reason)}"
            )
            return this.lifecycleAccountRow(entry, false, "not-started", reason, runtime)
        }
    }

    private func stopRegisteredEntry(entry: GatewayRegisteredAdapter, reason: String, manualStop: Bool): JsonObject {
        if (!this.liveAccountRunning(entry.channelId, entry.accountId)) {
            let runtime = gatewayChannelRuntimeMarkStopped(entry.channelId, accountId: entry.accountId, reason: "already-stopped", manualStop: manualStop)
            return this.lifecycleAccountRow(entry, true, "already-stopped", "", runtime)
        }
        try {
            entry.adapter.stop()
            this.updateLiveAccount(entry.channelId, entry.accountId, { state =>
                state.running = false
                state.connected = false
                state.lastError = if (manualStop) { "" } else { reason.trimAscii() }
            })
            let runtime = gatewayChannelRuntimeMarkStopped(entry.channelId, accountId: entry.accountId, reason: reason, manualStop: manualStop)
            gatewayLogEventInfo(
                "gateway/channel/${entry.channelId}",
                "channel.stopped",
                "channel account stopped",
                fields: "channel=${entry.channelId} accountId=${entry.accountId} phase=stop status=ok reason=${gatewayLogEventValue(reason)}"
            )
            return this.lifecycleAccountRow(entry, true, "stopped", "", runtime)
        } catch (e: Exception) {
            let safeReason = gatewaySanitizeChannelDiagnostic(e.message)
            this.updateLiveAccount(entry.channelId, entry.accountId, { state =>
                state.running = false
                state.connected = false
                state.lastError = safeReason
            })
            let runtime = gatewayChannelRuntimeMarkFailure(entry.channelId, accountId: entry.accountId, lifecycleState: "failed", error: safeReason)
            gatewayLogEventError(
                "gateway/channel/${entry.channelId}",
                "channel.failed",
                "channel account stop failed",
                fields: "channel=${entry.channelId} accountId=${entry.accountId} phase=stop status=failed errorKind=stop_failed error=${gatewayLogEventValue(safeReason)}"
            )
            return this.lifecycleAccountRow(entry, false, "not-stopped", safeReason, runtime)
        }
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
        gatewayLogEventInfo(
            "gateway/channel",
            "channel.registered",
            "channel account registered",
            fields: "channel=${registered.channelId} accountId=${registered.accountId} phase=register status=ok configured=${registered.configured} enabled=${registered.enabled}"
        )
    }

    public func getAdapter(name: String): Option<ChannelAdapter> {
        this.adapterByName.get(name)
    }

    private func rebuildAdapterByName(): Unit {
        this.adapterByName.clear()
        for (entry in this.adapters) {
            this.adapterByName[entry.adapter.name] = entry.adapter
        }
    }

    public func clearChannelRegistrations(channelId: String): Unit {
        let normalized = channelId.trimAscii().toAsciiLower()
        if (normalized.isEmpty()) {
            return
        }
        var idx: Int64 = this.adapters.size - 1
        while (idx >= 0) {
            if (this.adapters[idx].channelId == normalized) {
                let key = this.liveKey(this.adapters[idx].channelId, this.adapters[idx].accountId)
                synchronized(this.liveStateLock) {
                    this.liveAccounts.remove(key)
                }
                this.adapters.remove(at: idx)
            }
            idx -= 1
        }
        this.rebuildAdapterByName()
    }

    private func registeredAccountSummary(adapterName: String): String {
        let normalized = adapterName.trimAscii()
        let accounts = ArrayList<String>()
        for (entry in this.adapters) {
            if (entry.adapter.name == normalized) {
                accounts.add(entry.accountId)
            }
        }
        String.join(accounts.toArray(), delimiter: ",")
    }

    private func accountMismatchResult(adapterName: String, rawAccountId: String, canonicalAccountId: String): GatewayChannelSendResult {
        let registered = this.registeredAccountSummary(adapterName)
        GatewayChannelSendResult(
            false,
            lastReason: "adapter accountId mismatch for channel='${adapterName}' rawAccountId='${rawAccountId}' canonicalAccountId='${canonicalAccountId}' registeredAccounts='${registered}'",
            reasonKind: "account_mismatch",
            rawAccountId: rawAccountId,
            canonicalAccountId: canonicalAccountId
        )
    }

    private func notRegisteredResult(adapterName: String, rawAccountId: String, canonicalAccountId: String): GatewayChannelSendResult {
        GatewayChannelSendResult(
            false,
            lastReason: "adapter not registered for channel='${adapterName}'",
            reasonKind: "adapter_not_registered",
            rawAccountId: rawAccountId,
            canonicalAccountId: canonicalAccountId
        )
    }

    private func emptyMessageIdResult(adapterName: String, rawAccountId: String, canonicalAccountId: String): GatewayChannelSendResult {
        GatewayChannelSendResult(
            false,
            lastReason: "direct adapter returned empty message id for channel='${adapterName}' rawAccountId='${rawAccountId}' canonicalAccountId='${canonicalAccountId}'",
            reasonKind: "empty_message_id",
            rawAccountId: rawAccountId,
            canonicalAccountId: canonicalAccountId
        )
    }

    private func startEntry(entry: GatewayRegisteredAdapter): Unit {
        let entryStartMs = this.timingNowMs()
        if (!gatewayChannelRuntimeCanStart(entry.channelId, accountId: entry.accountId)) {
            gatewayLogEventInfo(
                "gateway/channel/${entry.channelId}",
                "channel.starting",
                "channel account start skipped",
                fields: "channel=${entry.channelId} accountId=${entry.accountId} phase=start status=skipped reason=runtime-start-suppressed"
            )
            this.timingLog("skip-cannot-start", entryStartMs, channelId: entry.channelId, accountId: entry.accountId)
            return
        }
        gatewayLogEventInfo(
            "gateway/channel/${entry.channelId}",
            "channel.starting",
            "channel account starting",
            fields: "channel=${entry.channelId} accountId=${entry.accountId} phase=start status=starting"
        )
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
            gatewayLogEventInfo(
                "gateway/channel/${entry.channelId}",
                "channel.started",
                "channel account running",
                fields: "channel=${entry.channelId} accountId=${entry.accountId} phase=start status=ok durationMs=${this.timingNowMs() - entryStartMs}"
            )
        } catch (e: Exception) {
            this.updateLiveAccount(entry.channelId, entry.accountId, { state =>
                state.configured = entry.configured
                state.running = false
                state.connected = false
                state.lastError = e.message.trimAscii()
            })
            gatewayChannelRuntimeMarkFailure(entry.channelId, accountId: entry.accountId, lifecycleState: "failed", error: e.message)
            gatewayLogEventError(
                "gateway/channel/${entry.channelId}",
                "channel.failed",
                "channel account start failed",
                fields: "channel=${entry.channelId} accountId=${entry.accountId} phase=start status=failed errorKind=start_failed error=${gatewayLogEventValue(e.message)}"
            )
            this.timingLog("start-failed", adapterStartMs, channelId: entry.channelId, accountId: entry.accountId)
            this.timingLog("entry-total-failed", entryStartMs, channelId: entry.channelId, accountId: entry.accountId)
        }
    }

    public func startChannels(): Unit {
        if (this.started) {
            return
        }
        let startMs = this.timingNowMs()
        for (entry in this.adapters) {
            this.startEntry(entry)
        }
        this.started = true
        this.timingLog("startChannels-total", startMs)
        gatewayLogEventInfo(
            "gateway/channel",
            "channel.startup_summary",
            "channel startup completed",
            fields: "phase=start status=ok accountCount=${this.adapters.size} durationMs=${this.timingNowMs() - startMs}"
        )
    }

    public func startChannel(channelId: String, accountId!: String = ""): JsonObject {
        let entries = this.matchingEntries(channelId, accountId)
        if (entries.size == 0) {
            return this.lifecycleMissingResult("start", channelId, accountId)
        }
        let result = this.channelLifecycleBase("start", channelId, accountId)
        let accounts = this.channelLifecycleAccounts(result)
        var ok = true
        var startedCount: Int64 = 0
        for (entry in entries) {
            let row = this.startRegisteredEntry(entry, false)
            accounts.add(row)
            let rowOk = try { row.get("ok").getOrThrow().asBool().getValue() } catch (_e: Exception) { false }
            let rowResult = try { row.get("result").getOrThrow().asString().getValue() } catch (_e: Exception) { "" }
            ok = ok && rowOk
            if (rowResult == "started" || rowResult == "already-running") {
                startedCount += 1
            }
        }
        result.put("ok", ok.toJsonValue())
        result.put("started", (startedCount > 0).toJsonValue())
        result.put("result", JsonString(if (startedCount > 0) { "started" } else { "not-started" }))
        result.put("accounts", accounts)
        result.put("manager", gatewayChannelManagerSummary(channelId))
        result
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
                gatewayLogEventInfo(
                    "gateway/channel/${entry.channelId}",
                    "channel.stopped",
                    "channel account stopped",
                    fields: "channel=${entry.channelId} accountId=${entry.accountId} phase=stop status=ok reason=${gatewayLogEventValue(reason)}"
                )
            } catch (e: Exception) {
                this.updateLiveAccount(entry.channelId, entry.accountId, { state =>
                    state.running = false
                    state.connected = false
                    state.lastError = e.message.trimAscii()
                })
                gatewayChannelRuntimeMarkFailure(entry.channelId, accountId: entry.accountId, lifecycleState: "failed", error: e.message)
                gatewayLogEventError(
                    "gateway/channel/${entry.channelId}",
                    "channel.failed",
                    "channel account stop failed",
                    fields: "channel=${entry.channelId} accountId=${entry.accountId} phase=stop status=failed errorKind=stop_failed error=${gatewayLogEventValue(e.message)}"
                )
            }
        }
        this.started = false
    }

    public func stopChannel(channelId: String, accountId!: String = "", reason!: String = "manual-stop", manualStop!: Bool = true): JsonObject {
        let entries = this.matchingEntries(channelId, accountId)
        if (entries.size == 0) {
            let result = this.lifecycleMissingResult("stop", channelId, accountId)
            result.put("result", JsonString("not-stopped"))
            return result
        }
        let result = this.channelLifecycleBase("stop", channelId, accountId)
        let accounts = this.channelLifecycleAccounts(result)
        var ok = true
        var stoppedCount: Int64 = 0
        for (entry in entries) {
            let row = this.stopRegisteredEntry(entry, reason, manualStop)
            accounts.add(row)
            let rowOk = try { row.get("ok").getOrThrow().asBool().getValue() } catch (_e: Exception) { false }
            let rowResult = try { row.get("result").getOrThrow().asString().getValue() } catch (_e: Exception) { "" }
            ok = ok && rowOk
            if (rowResult == "stopped" || rowResult == "already-stopped") {
                stoppedCount += 1
            }
        }
        result.put("ok", ok.toJsonValue())
        result.put("stopped", (stoppedCount > 0).toJsonValue())
        result.put("result", JsonString(if (stoppedCount > 0) { "stopped" } else { "not-stopped" }))
        result.put("accounts", accounts)
        result.put("manager", gatewayChannelManagerSummary(channelId))
        result
    }

    public func restartChannel(channelId: String, accountId!: String = "", reason!: String = "restart"): JsonObject {
        let entries = this.matchingEntries(channelId, accountId)
        if (entries.size == 0) {
            let result = this.lifecycleMissingResult("restart", channelId, accountId)
            result.put("result", JsonString("not-restarted"))
            return result
        }
        let stopped = this.stopChannel(channelId, accountId: accountId, reason: reason, manualStop: false)
        let started = this.startChannel(channelId, accountId: accountId)
        let result = this.channelLifecycleBase("restart", channelId, accountId)
        let ok = (try { stopped.get("ok").getOrThrow().asBool().getValue() } catch (_e: Exception) { false }) &&
            (try { started.get("ok").getOrThrow().asBool().getValue() } catch (_e: Exception) { false })
        result.put("ok", ok.toJsonValue())
        result.put("restarted", ok.toJsonValue())
        result.put("result", JsonString(if (ok) { "restarted" } else { "not-restarted" }))
        result.put("stop", stopped)
        result.put("start", started)
        result.put("manager", gatewayChannelManagerSummary(channelId))
        result
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
                gatewayLogEventInfo(
                    "gateway/channel/${entry.channelId}",
                    "channel.pull",
                    "channel pull completed",
                    fields: "channel=${entry.channelId} accountId=${entry.accountId} phase=pull status=ok inboundCount=${messages.size}"
                )
                for (message in messages) {
                    try {
                        handleInbound(message, entry.accountId)
                    } catch (e: Exception) {
                        this.updateLiveAccount(entry.channelId, entry.accountId, { state =>
                            state.running = true
                            state.connected = true
                            state.lastError = e.message.trimAscii()
                        })
                        gatewayChannelRuntimeMarkInboundFailure(entry.channelId, accountId: entry.accountId, error: e.message)
                        gatewayLogEventError(
                            "gateway/channel/${entry.channelId}",
                            "channel.failed",
                            "channel inbound handler failed",
                            fields: "channel=${channelToString(message.channel)} accountId=${entry.accountId} phase=inbound status=failed peerHash=${gatewayLogIdentityHash(message.peerId)} errorKind=inbound_failed error=${gatewayLogEventValue(e.message)}"
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
                gatewayLogEventError(
                    "gateway/channel/${entry.channelId}",
                    "channel.failed",
                    "channel pull failed",
                    fields: "channel=${entry.channelId} accountId=${entry.accountId} phase=pull status=failed errorKind=pull_failed error=${gatewayLogEventValue(e.message)}"
                )
            }
        }
    }

    public func sendToAdapterName(adapterName: String, outbound: OutboundMessage): GatewayChannelSendResult {
        let normalized = adapterName.trimAscii()
        let rawAccountId = outbound.accountId.trimAscii()
        let requiredAccountId = gatewayCanonicalChannelAccountId(normalized, rawAccountId)
        var lastReason: String = ""
        var foundAdapter = false
        var matchedAccount = false
        for (entry in this.adapters) {
            if (entry.adapter.name != normalized) {
                continue
            }
            foundAdapter = true
            if (entry.accountId != requiredAccountId) {
                continue
            }
            matchedAccount = true
            let sendResult = entry.adapter.send(outbound)
            match (sendResult) {
                case SendResult.Success =>
                    this.updateLiveAccount(entry.channelId, entry.accountId, { state =>
                        state.running = true
                        state.connected = true
                        state.lastError = ""
                    })
                    gatewayChannelRuntimeMarkSend(entry.channelId, accountId: entry.accountId, success: true)
                    gatewayLogEventInfo(
                        "gateway/channel/${entry.channelId}",
                        "channel.send",
                        "channel send completed",
                        fields: "channel=${entry.channelId} accountId=${entry.accountId} phase=send status=ok peerHash=${gatewayLogIdentityHash(outbound.peerId)} textLen=${outbound.text.size}"
                    )
                    return GatewayChannelSendResult(true, rawAccountId: rawAccountId, canonicalAccountId: requiredAccountId)
                case SendResult.Failed(reason) =>
                    let safeReason = gatewaySanitizeChannelDiagnostic(reason)
                    this.updateLiveAccount(entry.channelId, entry.accountId, { state =>
                        state.lastError = safeReason
                    })
                    gatewayChannelRuntimeMarkSend(entry.channelId, accountId: entry.accountId, success: false, detail: safeReason)
                    gatewayLogEventError(
                        "gateway/channel/${entry.channelId}",
                        "channel.failed",
                        "channel send failed",
                        fields: "channel=${entry.channelId} accountId=${entry.accountId} phase=send status=failed peerHash=${gatewayLogIdentityHash(outbound.peerId)} textLen=${outbound.text.size} errorKind=send_failed error=${gatewayLogEventValue(safeReason)}"
                    )
                    lastReason = "adapter send failed for channel='${normalized}' rawAccountId='${rawAccountId}' canonicalAccountId='${requiredAccountId}': ${safeReason}"
            }
        }
        if (!foundAdapter) {
            return this.notRegisteredResult(normalized, rawAccountId, requiredAccountId)
        }
        if (!matchedAccount) {
            return this.accountMismatchResult(normalized, rawAccountId, requiredAccountId)
        }
        GatewayChannelSendResult(
            false,
            lastReason: lastReason,
            reasonKind: "send_failed",
            rawAccountId: rawAccountId,
            canonicalAccountId: requiredAccountId
        )
    }

    public func sendWithMessageIdToAdapterName(adapterName: String, outbound: OutboundMessage): GatewayChannelSendResult {
        let normalized = adapterName.trimAscii()
        let rawAccountId = outbound.accountId.trimAscii()
        let requiredAccountId = gatewayCanonicalChannelAccountId(normalized, rawAccountId)
        var foundAdapter = false
        for (entry in this.adapters) {
            if (entry.adapter.name != normalized) {
                continue
            }
            foundAdapter = true
            if (entry.accountId != requiredAccountId) {
                continue
            }
            try {
                let sentMessageId = entry.adapter.sendWithMessageId(outbound)
                if (!sentMessageId.trimAscii().isEmpty()) {
                    this.updateLiveAccount(entry.channelId, entry.accountId, { state =>
                        state.running = true
                        state.connected = true
                        state.lastError = ""
                    })
                    gatewayChannelRuntimeMarkSend(entry.channelId, accountId: entry.accountId, success: true)
                    gatewayLogEventInfo(
                        "gateway/channel/${entry.channelId}",
                        "channel.send",
                        "channel direct send completed",
                        fields: "channel=${entry.channelId} accountId=${entry.accountId} phase=send status=ok peerHash=${gatewayLogIdentityHash(outbound.peerId)} textLen=${outbound.text.size} messageId=${gatewayLogEventValue(sentMessageId)}"
                    )
                    return GatewayChannelSendResult(
                        true,
                        messageId: sentMessageId,
                        rawAccountId: rawAccountId,
                        canonicalAccountId: requiredAccountId
                    )
                }
                return this.emptyMessageIdResult(normalized, rawAccountId, requiredAccountId)
            } catch (e: Exception) {
                let safeReason = gatewaySanitizeChannelDiagnostic(e.message)
                this.updateLiveAccount(entry.channelId, entry.accountId, { state =>
                    state.lastError = safeReason
                })
                gatewayChannelRuntimeMarkSend(entry.channelId, accountId: entry.accountId, success: false, detail: safeReason)
                gatewayLogEventError(
                    "gateway/channel/${entry.channelId}",
                    "channel.failed",
                    "channel direct send failed",
                    fields: "channel=${entry.channelId} accountId=${entry.accountId} phase=send status=failed peerHash=${gatewayLogIdentityHash(outbound.peerId)} textLen=${outbound.text.size} errorKind=send_failed error=${gatewayLogEventValue(safeReason)}"
                )
                return GatewayChannelSendResult(
                    false,
                    lastReason: "direct adapter send failed for channel='${normalized}' rawAccountId='${rawAccountId}' canonicalAccountId='${requiredAccountId}': ${safeReason}",
                    reasonKind: "send_failed",
                    rawAccountId: rawAccountId,
                    canonicalAccountId: requiredAccountId
                )
            }
        }
        if (!foundAdapter) {
            return this.notRegisteredResult(normalized, rawAccountId, requiredAccountId)
        }
        this.accountMismatchResult(normalized, rawAccountId, requiredAccountId)
    }
}
