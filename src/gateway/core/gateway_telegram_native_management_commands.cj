package metis.gateway.core

import metis.core.config.{CliConfig, GatewayUserSettings, MetisConfigManager}

import magic.jsonable.*

import std.collection.ArrayList
import std.fs.{Directory, File, Path, exists}
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private func tgMgmtNowMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toMilliseconds()
}

private func tgMgmtCommandJson(action: String, status: String, ok!: Bool = true, message!: String = ""): JsonObject {
    let out = JsonObject()
    out.put("ok", ok.toJsonValue())
    out.put("status", JsonString(status))
    out.put("action", JsonString(action))
    if (!message.trimAscii().isEmpty()) {
        out.put("message", JsonString(message.trimAscii()))
    }
    out
}

private func tgMgmtArgText(text: String): String {
    let parts = text.trimAscii().split(" ", 2)
    if (parts.size > 1) { parts[1].trimAscii() } else { "" }
}

private func tgMgmtJsonString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func tgMgmtApprovalStorePath(): Path {
    CliConfig.dotDir.join("exec-approvals.json")
}

private func tgMgmtReadApprovalRoot(): JsonObject {
    let path = tgMgmtApprovalStorePath()
    if (!exists(path)) {
        return JsonObject()
    }
    try {
        JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject()
    } catch (_: Exception) {
        JsonObject()
    }
}

public func gatewayTelegramCreateNativeApproval(
    action: String,
    requester: String,
    commandText: String,
    payload!: JsonObject = JsonObject()
): JsonObject {
    if (!exists(CliConfig.dotDir)) {
        Directory.create(CliConfig.dotDir, recursive: true)
    }
    let root = tgMgmtReadApprovalRoot()
    let approvals = match (root.get("approvals")) {
        case Some(v) => try { v.asArray() } catch (_: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let now = tgMgmtNowMs()
    let id = "tg-${action.replace(".", "-")}-${now}-${approvals.size() + 1}"
    let row = JsonObject()
    row.put("id", JsonString(id))
    row.put("approvalId", JsonString(id))
    row.put("status", JsonString("pending"))
    row.put("action", JsonString(action.trimAscii()))
    row.put("requester", JsonString(requester.trimAscii()))
    row.put("createdAtMs", now.toJsonValue())
    row.put("surface", JsonString("telegram-native-command"))
    row.put("command", JsonString(commandText.trimAscii()))
    row.put("payload", payload)
    approvals.add(row)
    root.put("approvals", approvals)
    File.writeTo(tgMgmtApprovalStorePath(), root.toJsonString().toArray())

    let out = tgMgmtCommandJson(action, "approval_required", ok: false, message: "Approval created; resolve it from Gateway approval controls or Telegram approval callback.")
    out.put("approvalId", JsonString(id))
    out.put("approvalPath", JsonString(tgMgmtApprovalStorePath().toString()))
    out.put("pendingAction", JsonString(action.trimAscii()))
    out
}

private func tgMgmtListStrings(values: Array<String>): JsonArray {
    let arr = JsonArray([])
    for (value in values) {
        arr.add(JsonString(value))
    }
    arr
}

private func tgMgmtSafeStoreSegment(raw: String): String {
    let trimmed = raw.trimAscii()
    let value = if (trimmed.isEmpty() || trimmed == "telegram:default") {
        "default"
    } else if (trimmed.startsWith("telegram:")) {
        trimmed["telegram:".size..].trimAscii().toAsciiLower()
    } else {
        trimmed.toAsciiLower()
    }
    let out = StringBuilder()
    for (r in value.runes()) {
        if ((r >= r'a' && r <= r'z') || (r >= r'A' && r <= r'Z') || (r >= r'0' && r <= r'9') || r == r'.' || r == r'_' || r == r'-') {
            out.append(r)
        } else {
            out.append(r'_')
        }
    }
    let normalized = out.toString().trimAscii()
    if (normalized.isEmpty()) { "default" } else { normalized }
}

private func tgMgmtPairingCredentialsDir(accountId: String): Path {
    CliConfig.dotDir.join("gateway-telegram").join("accounts").join(tgMgmtSafeStoreSegment(accountId)).join("credentials")
}

private func tgMgmtReadStringArray(path: Path): Array<String> {
    let out = ArrayList<String>()
    if (!exists(path)) {
        return out.toArray()
    }
    try {
        let arr = JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asArray()
        for (item in arr.getItems()) {
            try {
                let value = item.asString().getValue().trimAscii()
                if (!value.isEmpty()) {
                    out.add(value)
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

private func tgMgmtPendingPairingCount(accountId: String): Int64 {
    let path = tgMgmtPairingCredentialsDir(accountId).join("telegram-pairing.json")
    if (!exists(path)) {
        return 0
    }
    try {
        JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asArray().size()
    } catch (_: Exception) {
        0
    }
}

public func gatewayTelegramRenderAllowlistCommand(
    text: String,
    user: GatewayUserSettings,
    accountId: String,
    senderId: String
): String {
    let argText = tgMgmtArgText(text)
    let args = argText.split(" ")
    let action = if (args.size > 0 && !args[0].trimAscii().isEmpty()) { args[0].trimAscii().toAsciiLower() } else { "list" }
    let scope = if (args.size > 1 && !args[1].trimAscii().isEmpty()) { args[1].trimAscii().toAsciiLower() } else { "all" }
    let pairingApproved = tgMgmtReadStringArray(tgMgmtPairingCredentialsDir(accountId).join("telegram-allowFrom.json"))
    if (action == "list") {
        let out = tgMgmtCommandJson("allowlist", "ok")
            out.put("requested", JsonString("list"))
        out.put("scope", JsonString(scope))
        if (scope == "dm" || scope == "all") {
            out.put("allowFrom", tgMgmtListStrings(user.telegram.allowFrom))
            out.put("pairingApproved", tgMgmtListStrings(pairingApproved))
            out.put("pairingPendingCount", tgMgmtPendingPairingCount(accountId).toJsonValue())
        }
        if (scope == "group" || scope == "all") {
            out.put("groupAllowFrom", tgMgmtListStrings(user.telegram.groupAllowFrom))
        }
        return out.toJsonString()
    }
    if (!(action == "add" || action == "remove")) {
        return tgMgmtCommandJson("allowlist", "usage", ok: false, message: "usage: /allowlist list [dm|group|all] | /allowlist add|remove dm|group <entry>").toJsonString()
    }
    if (!(scope == "dm" || scope == "group") || args.size < 3) {
        return tgMgmtCommandJson("allowlist", "usage", ok: false, message: "usage: /allowlist add|remove dm|group <entry>").toJsonString()
    }
    let entry = args[2].trimAscii()
    if (entry.isEmpty()) {
        return tgMgmtCommandJson("allowlist", "usage", ok: false, message: "allowlist entry is required").toJsonString()
    }
    let payload = JsonObject()
    payload.put("scope", JsonString(scope))
    payload.put("entry", JsonString(entry))
    payload.put("store", JsonString(if (scope == "dm") { "telegram-pairing-store" } else { "gateway.telegram.groupAllowFrom" }))
    let approval = gatewayTelegramCreateNativeApproval("telegram.allowlist.${action}", senderId, text, payload: payload)
    approval.put("action", JsonString("allowlist"))
    approval.put("requested", JsonString(action))
    approval.put("scope", JsonString(scope))
    approval.put("entry", JsonString(entry))
    approval.toJsonString()
}

private func tgMgmtTranscriptMessageCount(raw: String): Int64 {
    var count: Int64 = 0
    for (line in raw.split("\n")) {
        let t = line.trimAscii()
        if (t.contains("\"role\"") && t.contains("\"text\"")) {
            count += 1
        }
    }
    count
}

private func tgMgmtSessionPreview(raw: String, maxEntries: Int64): String {
    let lines = ArrayList<String>()
    for (line in raw.split("\n")) {
        let t = line.trimAscii()
        if (!t.contains("\"role\"") || !t.contains("\"text\"")) {
            continue
        }
        try {
            let obj = JsonValue.fromStr(t).asObject()
            let role = tgMgmtJsonString(obj, "role")
            if (role == "system") {
                continue
            }
            let body = tgMgmtJsonString(obj, "text")
            if (!body.isEmpty()) {
                lines.add("[${role}] ${body}")
            }
        } catch (_: Exception) {
            ()
        }
    }
    if (lines.isEmpty()) {
        return "(no user/assistant transcript entries)"
    }
    let start = max(0, lines.size - maxEntries)
    let out = ArrayList<String>()
    var i = start
    while (i < lines.size) {
        out.add(lines[i])
        i += 1
    }
    String.join(out.toArray(), delimiter: "\n\n")
}

public func gatewayTelegramRenderSessionsCommand(text: String, user: GatewayUserSettings): String {
    let args = tgMgmtArgText(text).split(" ", 2)
    let action = if (args.size > 0 && !args[0].trimAscii().isEmpty()) { args[0].trimAscii().toAsciiLower() } else { "list" }
    let store = gatewaySessionStoreForUser(user)
    if (action == "path") {
        let out = tgMgmtCommandJson("sessions", "ok")
        out.put("requested", JsonString("path"))
        out.put("root", JsonString(store.sessionsRoot().toString()))
        out.put("message", JsonString("This is the Metis Gateway session root for the active METIS_HOME."))
        return out.toJsonString()
    }
    if (action == "preview") {
        let key = if (args.size > 1) { args[1].trimAscii() } else { "" }
        if (key.isEmpty()) {
            return tgMgmtCommandJson("sessions", "usage", ok: false, message: "usage: /sessions preview <sessionKey>").toJsonString()
        }
        let raw = match (store.readTranscriptRaw(key)) {
            case Some(v) => v
            case None => ""
        }
        let out = tgMgmtCommandJson("sessions", if (raw.isEmpty()) { "not_found" } else { "ok" }, ok: !raw.isEmpty())
        out.put("requested", JsonString("preview"))
        out.put("sessionKey", JsonString(key))
        out.put("preview", JsonString(if (raw.isEmpty()) { "" } else { store.formatHistoryAsText(key, 6) }))
        return out.toJsonString()
    }
    if (!(action == "list" || action.isEmpty())) {
        return tgMgmtCommandJson("sessions", "usage", ok: false, message: "usage: /sessions list | /sessions path | /sessions preview <sessionKey>").toJsonString()
    }
    let keys = store.listSessionKeys()
    let indexRoot = store.readSessionsIndexRoot()
    let rows = JsonArray([])
    for (key in keys) {
        let row = JsonObject()
        row.put("sessionKey", JsonString(key))
        match (indexRoot.get(key)) {
            case Some(v) =>
                try {
                    let entry = v.asObject()
                    match (entry.get("updatedAt")) { case Some(u) => row.put("updatedAt", u) case None => () }
                    match (entry.get("sessionFile")) { case Some(f) => row.put("sessionFile", f) case None => () }
                } catch (_: Exception) {
                    ()
                }
            case None => ()
        }
        match (store.readTranscriptRaw(key)) {
            case Some(raw) => row.put("messageCount", tgMgmtTranscriptMessageCount(raw).toJsonValue())
            case None => row.put("messageCount", 0.toJsonValue())
        }
        let binding = store.readLatestBindingSnapshot(key)
        if (binding.size() > 0) {
            row.put("binding", binding)
        }
        rows.add(row)
    }
    let out = tgMgmtCommandJson("sessions", "ok")
    out.put("requested", JsonString("list"))
    out.put("count", Int64(keys.size).toJsonValue())
    out.put("sessions", rows)
    out.toJsonString()
}

public func gatewayTelegramRenderApprovalsCommand(): String {
    let root = tgMgmtReadApprovalRoot()
    let rows = JsonArray([])
    let approvals = match (root.get("approvals")) {
        case Some(v) => try { v.asArray() } catch (_: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    for (item in approvals.getItems()) {
        try {
            let row = item.asObject()
            let status = tgMgmtJsonString(row, "status")
            if (status == "pending" || status.isEmpty()) {
                rows.add(row)
            }
        } catch (_: Exception) {
            ()
        }
    }
    let out = tgMgmtCommandJson("approvals", "ok")
    out.put("pendingCount", Int64(rows.size()).toJsonValue())
    out.put("approvals", rows)
    out.put("path", JsonString(tgMgmtApprovalStorePath().toString()))
    out.toJsonString()
}

public func gatewayTelegramRenderConfigMutationApproval(command: String, text: String, senderId: String, message: String): String {
    let payload = JsonObject()
    payload.put("command", JsonString(command))
    payload.put("raw", JsonString(text.trimAscii()))
    let out = gatewayTelegramCreateNativeApproval("telegram.${command}.mutation", senderId, text, payload: payload)
    out.put("action", JsonString(command))
    out.put("message", JsonString(message))
    out.toJsonString()
}
