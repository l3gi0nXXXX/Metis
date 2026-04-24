package metis.gateway.channels.telegram

import metis.core.config.CliConfig

import magic.jsonable.*

import std.collection.ArrayList
import std.convert.Parsable
import std.fs.{Directory, File, Path, exists}
import std.random.Random
import std.time.DateTime
import stdx.encoding.json.*

private let TELEGRAM_PAIRING_TTL_MS: Int64 = 60 * 60 * 1000
private let TELEGRAM_PAIRING_CODE_LEN: Int64 = 8

public class TelegramPairingStore {
    private let rootDir: Path

    public init(rootDir!: Path = CliConfig.dotDir) {
        this.rootDir = rootDir
    }

    public func isApproved(senderId: String): Bool {
        let normalizedSender = normalizeTelegramPairingSenderId(senderId)
        for (approved in this.readApprovedSenders()) {
            if (normalizeTelegramPairingSenderId(approved) == normalizedSender) {
                return true
            }
        }
        false
    }

    public func ensurePending(senderId: String): String {
        let nowMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
        let normalizedSender = normalizeTelegramPairingSenderId(senderId)
        let rows = this.readPendingRows()
        let kept = ArrayList<JsonObject>()
        var existingCode = ""
        for (row in rows) {
            let expiresAtMs = readPairingInt(row, "expiresAtMs", 0)
            if (expiresAtMs < nowMs) {
                continue
            }
            let rowSender = normalizeTelegramPairingSenderId(readPairingString(row, "senderId"))
            if (rowSender == normalizedSender && existingCode.isEmpty()) {
                existingCode = readPairingString(row, "code")
            }
            kept.add(row)
        }
        if (!existingCode.isEmpty()) {
            this.writePendingRows(kept)
            return existingCode
        }
        let code = generateTelegramPairingCode()
        let row = JsonObject()
        row.put("senderId", JsonString(normalizedSender))
        row.put("code", JsonString(code))
        row.put("createdAtMs", nowMs.toJsonValue())
        row.put("expiresAtMs", (nowMs + TELEGRAM_PAIRING_TTL_MS).toJsonValue())
        kept.add(row)
        this.writePendingRows(kept)
        code
    }

    public func approve(code: String): Bool {
        let normalizedCode = code.trimAscii().toAsciiUpper()
        if (normalizedCode.isEmpty()) {
            return false
        }
        let nowMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
        let rows = this.readPendingRows()
        let kept = ArrayList<JsonObject>()
        var approvedSender = ""
        for (row in rows) {
            let expiresAtMs = readPairingInt(row, "expiresAtMs", 0)
            if (expiresAtMs < nowMs) {
                continue
            }
            let rowCode = readPairingString(row, "code").trimAscii().toAsciiUpper()
            if (approvedSender.isEmpty() && rowCode == normalizedCode) {
                approvedSender = normalizeTelegramPairingSenderId(readPairingString(row, "senderId"))
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
            let normalized = normalizeTelegramPairingSenderId(sender)
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

    public func pendingCodeForSender(senderId: String): String {
        let normalizedSender = normalizeTelegramPairingSenderId(senderId)
        let nowMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
        for (row in this.readPendingRows()) {
            if (readPairingInt(row, "expiresAtMs", 0) < nowMs) {
                continue
            }
            if (normalizeTelegramPairingSenderId(readPairingString(row, "senderId")) == normalizedSender) {
                return readPairingString(row, "code")
            }
        }
        ""
    }

    public func pendingRows(): Array<JsonObject> {
        let nowMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
        let kept = ArrayList<JsonObject>()
        for (row in this.readPendingRows()) {
            if (readPairingInt(row, "expiresAtMs", 0) < nowMs) {
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
        this.credentialsDir().join("telegram-pairing.json")
    }

    private func approvedPath(): Path {
        this.credentialsDir().join("telegram-allowFrom.json")
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
        let path = this.approvedPath()
        if (!exists(path)) {
            return []
        }
        try {
            let arr = JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asArray()
            let out = ArrayList<String>()
            for (item in arr.getItems()) {
                try {
                    let text = item.asString().getValue().trimAscii()
                    if (!text.isEmpty()) {
                        out.add(text)
                    }
                } catch (_: Exception) {
                    ()
                }
            }
            out.toArray()
        } catch (_: Exception) {
            []
        }
    }

    private func writeApprovedSenders(senders: Array<String>): Unit {
        let arr = JsonArray([])
        for (sender in senders) {
            arr.add(sender.toJsonValue())
        }
        File.writeTo(this.approvedPath(), arr.toJsonString().toArray())
    }
}

private func readPairingString(row: JsonObject, key: String): String {
    match (row.get(key)) {
        case Some(v) =>
            try { v.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func readPairingInt(row: JsonObject, key: String, fallback: Int64): Int64 {
    match (row.get(key)) {
        case Some(v) =>
            try { Int64.parse(v.toJsonString()) } catch (_: Exception) { fallback }
        case None => fallback
    }
}

private func normalizeTelegramPairingSenderId(raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed.startsWith("telegram:")) {
        return trimmed["telegram:".size..].trimAscii()
    }
    if (trimmed.startsWith("tg:")) {
        return trimmed["tg:".size..].trimAscii()
    }
    if (trimmed.startsWith("user:")) {
        return trimmed["user:".size..].trimAscii()
    }
    trimmed
}

private func generateTelegramPairingCode(): String {
    let rand = Random()
    let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".toRuneArray()
    let out = StringBuilder()
    for (_ in 0..TELEGRAM_PAIRING_CODE_LEN) {
        let raw = rand.nextInt64()
        let idx = Int64((raw % chars.size + chars.size) % chars.size)
        out.append(chars[idx])
    }
    out.toString()
}
