package metis.gateway.security

import metis.core.config.CliConfig

import magic.jsonable.*

import std.collection.ArrayList
import std.convert.Parsable
import std.fs.{Directory, File, Path, exists}
import std.random.Random
import std.time.DateTime
import stdx.encoding.json.*

private let GATEWAY_PAIRING_TTL_MS: Int64 = 60 * 60 * 1000
private let GATEWAY_PAIRING_CODE_LEN: Int64 = 8
private let GATEWAY_PAIRING_DEFAULT_ACCOUNT_ID = "default"

public func gatewayPairingAccountStore(
    channel!: String,
    accountId!: String,
    rootDir!: Path = CliConfig.dotDir
): GatewayPairingStore {
    GatewayPairingStore(channel: channel, accountId: accountId, rootDir: rootDir)
}

public func gatewayPairingAccountStateDir(
    rootDir: Path,
    channel: String,
    accountId: String
): Path {
    let normalizedChannel = gatewayNormalizePairingChannel(channel)
    let normalizedAccount = gatewayNormalizePairingAccountId(normalizedChannel, accountId)
    let root = rootDir.join("gateway-${safeGatewayPairingStateSegment(normalizedChannel, fallback: "channel")}")
    if (!exists(root)) {
        Directory.create(root, recursive: true)
    }
    let dir = root.join("accounts").join(safeGatewayPairingStateSegment(normalizedAccount, fallback: GATEWAY_PAIRING_DEFAULT_ACCOUNT_ID))
    if (!exists(dir)) {
        Directory.create(dir, recursive: true)
    }
    dir
}

public func gatewayNormalizePairingChannel(raw: String): String {
    let normalized = raw.trimAscii().toAsciiLower()
    if (normalized.isEmpty()) { "channel" } else { normalized }
}

public func gatewayNormalizePairingAccountId(channel: String, raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return GATEWAY_PAIRING_DEFAULT_ACCOUNT_ID
    }
    let normalizedChannel = gatewayNormalizePairingChannel(channel)
    let prefix = "${normalizedChannel}:"
    if (trimmed.toAsciiLower().startsWith(prefix)) {
        let suffix = trimmed[prefix.size..].trimAscii()
        return if (suffix.isEmpty()) { GATEWAY_PAIRING_DEFAULT_ACCOUNT_ID } else { suffix }
    }
    trimmed
}

public class GatewayPairingStore {
    private let channel: String
    private let accountId: String
    private let rootDir: Path

    public init(channel!: String, accountId!: String, rootDir!: Path = CliConfig.dotDir) {
        this.channel = gatewayNormalizePairingChannel(channel)
        this.accountId = gatewayNormalizePairingAccountId(this.channel, accountId)
        this.rootDir = gatewayPairingAccountStateDir(rootDir, this.channel, this.accountId)
    }

    public func rootPath(): Path {
        this.rootDir
    }

    public func isApproved(senderId: String): Bool {
        let normalizedSender = this.normalizeSenderId(senderId)
        for (approved in this.readApprovedSenders()) {
            if (this.normalizeSenderId(approved) == normalizedSender) {
                return true
            }
        }
        false
    }

    public func ensurePending(senderId: String): String {
        let nowMs = gatewayPairingNowMs()
        let normalizedSender = this.normalizeSenderId(senderId)
        let rows = this.readPendingRows()
        let kept = ArrayList<JsonObject>()
        var existingCode = ""
        for (row in rows) {
            let expiresAtMs = gatewayReadPairingInt(row, "expiresAtMs", 0)
            if (expiresAtMs < nowMs) {
                continue
            }
            let rowSender = this.normalizeSenderId(gatewayReadPairingString(row, "senderId"))
            if (rowSender == normalizedSender && existingCode.isEmpty()) {
                existingCode = gatewayReadPairingString(row, "code")
            }
            kept.add(row)
        }
        if (!existingCode.isEmpty()) {
            this.writePendingRows(kept)
            return existingCode
        }
        let code = generateGatewayPairingCode()
        let row = JsonObject()
        row.put("senderId", JsonString(normalizedSender))
        row.put("code", JsonString(code))
        row.put("createdAtMs", nowMs.toJsonValue())
        row.put("expiresAtMs", (nowMs + GATEWAY_PAIRING_TTL_MS).toJsonValue())
        kept.add(row)
        this.writePendingRows(kept)
        code
    }

    public func pendingCodeForSender(senderId: String): String {
        let normalizedSender = this.normalizeSenderId(senderId)
        let nowMs = gatewayPairingNowMs()
        for (row in this.readPendingRows()) {
            if (gatewayReadPairingInt(row, "expiresAtMs", 0) < nowMs) {
                continue
            }
            if (this.normalizeSenderId(gatewayReadPairingString(row, "senderId")) == normalizedSender) {
                return gatewayReadPairingString(row, "code")
            }
        }
        ""
    }

    public func approve(code: String): Bool {
        let normalizedCode = code.trimAscii().toAsciiUpper()
        if (normalizedCode.isEmpty()) {
            return false
        }
        let nowMs = gatewayPairingNowMs()
        let rows = this.readPendingRows()
        let kept = ArrayList<JsonObject>()
        var approvedSender = ""
        for (row in rows) {
            let expiresAtMs = gatewayReadPairingInt(row, "expiresAtMs", 0)
            if (expiresAtMs < nowMs) {
                continue
            }
            let rowCode = gatewayReadPairingString(row, "code").trimAscii().toAsciiUpper()
            if (approvedSender.isEmpty() && rowCode == normalizedCode) {
                approvedSender = this.normalizeSenderId(gatewayReadPairingString(row, "senderId"))
                continue
            }
            kept.add(row)
        }
        if (approvedSender.isEmpty()) {
            return false
        }
        let approved = ArrayList<String>()
        var seen = false
        for (sender in this.readApprovedSenders()) {
            let normalized = this.normalizeSenderId(sender)
            if (normalized == approvedSender) {
                seen = true
            }
            approved.add(normalized)
        }
        if (!seen) {
            approved.add(approvedSender)
        }
        this.writePendingRows(kept)
        this.writeApprovedSenders(approved.toArray())
        true
    }

    public func pendingRows(): Array<JsonObject> {
        let nowMs = gatewayPairingNowMs()
        let kept = ArrayList<JsonObject>()
        for (row in this.readPendingRows()) {
            if (gatewayReadPairingInt(row, "expiresAtMs", 0) < nowMs) {
                continue
            }
            kept.add(row)
        }
        kept.toArray()
    }

    public func approvedSenders(): Array<String> {
        this.readApprovedSenders()
    }

    private func credentialsDir(): Path {
        let dir = this.rootDir.join("credentials")
        if (!exists(dir)) {
            Directory.create(dir, recursive: true)
        }
        dir
    }

    private func pendingPath(): Path {
        this.credentialsDir().join("${this.channel}-pairing.json")
    }

    private func approvedPath(): Path {
        this.credentialsDir().join("${this.channel}-allowFrom.json")
    }

    private func readPendingRows(): Array<JsonObject> {
        let path = this.pendingPath()
        if (!exists(path)) {
            return []
        }
        try {
            let arr = JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asArray()
            let out = ArrayList<JsonObject>()
            for (item in arr.getItems()) {
                try {
                    out.add(item.asObject())
                } catch (_: Exception) {
                    ()
                }
            }
            out.toArray()
        } catch (_: Exception) {
            []
        }
    }

    private func writePendingRows(rows: ArrayList<JsonObject>): Unit {
        let arr = JsonArray([])
        for (row in rows) {
            arr.add(row.toJsonValue())
        }
        File.writeTo(this.pendingPath(), arr.toJsonString().toArray())
    }

    private func readApprovedSenders(): Array<String> {
        let out = ArrayList<String>()
        if (!exists(this.approvedPath())) {
            return []
        }
        try {
            let arr = JsonValue.fromStr(String.fromUtf8(File.readFrom(this.approvedPath()))).asArray()
            for (item in arr.getItems()) {
                try {
                    let normalized = this.normalizeSenderId(item.asString().getValue())
                    if (!normalized.isEmpty() && !gatewayPairingStringListContains(out, normalized)) {
                        out.add(normalized)
                    }
                } catch (_: Exception) {
                    ()
                }
            }
        } catch (_: Exception) {
            ()
        }
        out.toArray()
    }

    private func writeApprovedSenders(senders: Array<String>): Unit {
        let arr = JsonArray([])
        for (sender in senders) {
            arr.add(this.normalizeSenderId(sender).toJsonValue())
        }
        File.writeTo(this.approvedPath(), arr.toJsonString().toArray())
    }

    private func normalizeSenderId(raw: String): String {
        let trimmed = raw.trimAscii()
        let prefix = "${this.channel}:"
        if (trimmed.toAsciiLower().startsWith(prefix)) {
            return trimmed[prefix.size..].trimAscii()
        }
        if (trimmed.startsWith("user:")) {
            return trimmed["user:".size..].trimAscii()
        }
        trimmed
    }
}

private func gatewayPairingNowMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toMilliseconds()
}

private func gatewayPairingStringListContains(values: ArrayList<String>, target: String): Bool {
    let normalized = target.trimAscii()
    for (value in values) {
        if (value.trimAscii() == normalized) {
            return true
        }
    }
    false
}

private func safeGatewayPairingStateSegment(raw: String, fallback!: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return fallback
    }
    let out = StringBuilder()
    for (r in trimmed.runes()) {
        if ((r >= r'a' && r <= r'z') || (r >= r'A' && r <= r'Z') || (r >= r'0' && r <= r'9') || r == r'.' || r == r'_' || r == r'-') {
            out.append(r)
        } else {
            out.append(r'_')
        }
    }
    let normalized = out.toString().trimAscii()
    if (normalized.isEmpty()) { fallback } else { normalized }
}

private func gatewayReadPairingString(row: JsonObject, key: String): String {
    match (row.get(key)) {
        case Some(v) =>
            try { v.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func gatewayReadPairingInt(row: JsonObject, key: String, fallback: Int64): Int64 {
    match (row.get(key)) {
        case Some(v) =>
            try { Int64.parse(v.toJsonString()) } catch (_: Exception) { fallback }
        case None => fallback
    }
}

private func generateGatewayPairingCode(): String {
    let rand = Random()
    let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".toRuneArray()
    let out = StringBuilder()
    for (_ in 0..GATEWAY_PAIRING_CODE_LEN) {
        let raw = rand.nextInt64()
        let idx = Int64((raw % chars.size + chars.size) % chars.size)
        out.append(chars[idx])
    }
    out.toString()
}
