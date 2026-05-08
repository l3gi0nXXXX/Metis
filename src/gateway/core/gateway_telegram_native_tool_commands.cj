package metis.gateway.core

import metis.core.{gatewaySubagentFindRunBySessionKey, gatewaySubagentMarkRunCancelled, gatewaySubagentRunRecordString}
import metis.core.config.{CliConfig, GatewayUserSettings}
import metis.core.skills.SkillsPrompt

import magic.jsonable.*

import std.convert.Parsable
import std.fs.{Directory, File, Path, exists}
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private func tgToolNowMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toMilliseconds()
}

private func tgToolCommandJson(action: String, status: String, ok!: Bool = true, message!: String = ""): JsonObject {
    let out = JsonObject()
    out.put("ok", ok.toJsonValue())
    out.put("status", JsonString(status))
    out.put("action", JsonString(action))
    if (!message.trimAscii().isEmpty()) {
        out.put("message", JsonString(message.trimAscii()))
    }
    out
}

private func tgToolArgText(text: String): String {
    let parts = text.trimAscii().split(" ", 2)
    if (parts.size > 1) { parts[1].trimAscii() } else { "" }
}

private func tgToolJsonString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func tgToolJsonInt(obj: JsonObject, key: String, fallback: Int64): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            try { Int64.parse(v.toJsonString()) } catch (_: Exception) {
                try { Int64.parse(v.asString().getValue().trimAscii()) } catch (_inner: Exception) { fallback }
            }
        case None => fallback
    }
}

public func gatewayTelegramRenderBashCommand(text: String, senderId: String): String {
    let command = tgToolArgText(text)
    if (command.isEmpty()) {
        return tgToolCommandJson("bash", "usage", ok: false, message: "usage: /bash <command>").toJsonString()
    }
    let payload = JsonObject()
    payload.put("command", JsonString(command))
    payload.put("executeAfterApproval", true.toJsonValue())
    let out = gatewayTelegramCreateNativeApproval("telegram.bash.exec", senderId, text, payload: payload)
    out.put("action", JsonString("bash"))
    out.put("command", JsonString(command))
    out.put("message", JsonString("Host shell execution was not run from Telegram. Approval is required before Gateway exec tooling may execute it."))
    out.toJsonString()
}

public func gatewayTelegramRenderRestartCommand(text: String, senderId: String): String {
    let payload = JsonObject()
    payload.put("controlAction", JsonString("restart"))
    payload.put("executeAfterApproval", true.toJsonValue())
    let out = gatewayTelegramCreateNativeApproval("telegram.gateway.restart", senderId, text, payload: payload)
    out.put("action", JsonString("restart"))
    out.put("message", JsonString("Gateway restart was not executed from Telegram. Approval is required before the Gateway control surface may restart."))
    out.toJsonString()
}

private func tgToolStatusTerminal(status: String): Bool {
    let s = status.trimAscii().toAsciiLower()
    s == "succeeded" || s == "failed" || s == "cancelled" || s == "canceled" || s == "timed_out"
}

public func gatewayTelegramRenderStopCommand(user: GatewayUserSettings, sessionKey: String): String {
    let store = gatewaySessionStoreForUser(user)
    match (gatewaySubagentFindRunBySessionKey(store.sessionsRoot(), sessionKey)) {
        case Some(record) =>
            let runId = gatewaySubagentRunRecordString(record, "runId")
            let status = gatewaySubagentRunRecordString(record, "status")
            if (tgToolStatusTerminal(status)) {
                let out = tgToolCommandJson("stop", "no_active_run", message: "The latest subagent run for this Telegram session is already terminal.")
                out.put("sessionKey", JsonString(sessionKey))
                out.put("runId", JsonString(runId))
                out.put("runStatus", JsonString(status))
                return out.toJsonString()
            }
            let cancelled = gatewaySubagentMarkRunCancelled(store.sessionsRoot(), runId, reason: "cancelled by Telegram /stop")
            let out = tgToolCommandJson("stop", if (cancelled) { "cancelled" } else { "error" }, ok: cancelled)
            out.put("sessionKey", JsonString(sessionKey))
            out.put("runId", JsonString(runId))
            out.put("previousStatus", JsonString(status))
            return out.toJsonString()
        case None =>
            let out = tgToolCommandJson("stop", "no_active_run", message: "No active Gateway subagent run is tracked for this Telegram session.")
            out.put("sessionKey", JsonString(sessionKey))
            out.toJsonString()
    }
}

public func gatewayTelegramRenderSkillCommand(text: String): String {
    let argText = tgToolArgText(text)
    let parts = argText.split(" ", 2)
    let name = if (parts.size > 0) { parts[0].trimAscii() } else { "" }
    if (name.isEmpty() || name == "list" || name == "status") {
        let rows = JsonArray([])
        for (skill in SkillsPrompt.listSkillDescriptors()) {
            let row = JsonObject()
            row.put("name", JsonString(skill.name))
            row.put("description", JsonString(skill.description))
            row.put("enabled", skill.enabled.toJsonValue())
            row.put("source", JsonString(skill.source))
            row.put("location", JsonString(skill.location))
            rows.add(row)
        }
        let out = tgToolCommandJson("skill", "ok")
        out.put("requested", JsonString(if (name.isEmpty()) { "list" } else { name }))
        out.put("skills", rows)
        return out.toJsonString()
    }
    if (!SkillsPrompt.hasSkillName(name)) {
        let out = tgToolCommandJson("skill", "not_found", ok: false, message: "No skill named '${name}' is available to this Gateway session.")
        out.put("skill", JsonString(name))
        return out.toJsonString()
    }
    let input = if (parts.size > 1) { parts[1].trimAscii() } else { "" }
    let out = tgToolCommandJson("skill", "ok", message: "Native skill dispatch is deterministic. Send /${name} ${input} as a normal turn when model-backed skill execution is desired.")
    out.put("skill", JsonString(name))
    out.put("input", JsonString(input))
    out.put("native", true.toJsonValue())
    out.toJsonString()
}

public func gatewayTelegramRenderBtwCommand(text: String, sessionKey: String): String {
    let question = tgToolArgText(text)
    if (question.isEmpty()) {
        return tgToolCommandJson("btw", "usage", ok: false, message: "usage: /btw <question>").toJsonString()
    }
    let out = tgToolCommandJson("btw", "ok", message: "Side question accepted as a non-persistent Telegram native command. It is not appended as a normal user/assistant turn.")
    out.put("sessionKey", JsonString(sessionKey))
    out.put("question", JsonString(question))
    out.put("persistent", false.toJsonValue())
    out.toJsonString()
}

private func tgToolTtsDir(): Path {
    let dir = CliConfig.dotDir.join("gateway-telegram").join("tts")
    if (!exists(dir)) {
        Directory.create(dir, recursive: true)
    }
    dir
}

private func tgToolTtsStatePath(): Path {
    tgToolTtsDir().join("state.json")
}

private func tgToolReadTtsState(): JsonObject {
    let path = tgToolTtsStatePath()
    if (!exists(path)) {
        let out = JsonObject()
        out.put("enabled", true.toJsonValue())
        out.put("provider", JsonString(""))
        out.put("limit", 4000.toJsonValue())
        out.put("audioAsVoice", true.toJsonValue())
        return out
    }
    try {
        JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject()
    } catch (_: Exception) {
        JsonObject()
    }
}

private func tgToolWriteTtsState(state: JsonObject): Unit {
    File.writeTo(tgToolTtsStatePath(), state.toJsonString().toArray())
}

private func tgToolTtsProviderFromExtra(user: GatewayUserSettings): String {
    match (user.channelsExtra) {
        case Some(extra) =>
            match (extra.get("telegramTts")) {
                case Some(v) =>
                    try {
                        return tgToolJsonString(v.asObject(), "provider")
                    } catch (_: Exception) {
                        return ""
                    }
                case None => ""
            }
        case None => ""
    }
}

private func tgToolTtsStatus(user: GatewayUserSettings, state: JsonObject): JsonObject {
    let configuredProvider = tgToolTtsProviderFromExtra(user)
    let stateProvider = tgToolJsonString(state, "provider")
    let provider = if (!stateProvider.isEmpty()) { stateProvider } else { configuredProvider }
    let enabled = match (state.get("enabled")) {
        case Some(v) => try { v.asBool().getValue() } catch (_: Exception) { true }
        case None => true
    }
    let status = if (provider.isEmpty()) { "not_configured" } else if (provider == "fake") { "ok" } else { "not_found" }
    let out = tgToolCommandJson("tts", status, ok: status == "ok")
    out.put("enabled", enabled.toJsonValue())
    out.put("provider", JsonString(provider))
    out.put("limit", tgToolJsonInt(state, "limit", 4000).toJsonValue())
    out.put("audioAsVoice", true.toJsonValue())
    if (provider.isEmpty()) {
        out.put("message", JsonString("No Metis TTS provider is configured for Telegram native voice output."))
    } else if (status == "not_found") {
        out.put("message", JsonString("Configured TTS provider '${provider}' is not available in this Gateway build."))
    }
    out
}

private func tgToolWriteFakeAudio(text: String): Path {
    let path = tgToolTtsDir().join("tts-${tgToolNowMs()}.ogg")
    File.writeTo(path, ("FAKE-OGG\n${text}").toArray())
    path
}

public func gatewayTelegramRenderTtsCommand(text: String, user: GatewayUserSettings): String {
    let argText = tgToolArgText(text)
    let parts = argText.split(" ", 2)
    let action = if (parts.size > 0 && !parts[0].trimAscii().isEmpty()) { parts[0].trimAscii().toAsciiLower() } else { "status" }
    let value = if (parts.size > 1) { parts[1].trimAscii() } else { "" }
    let state = tgToolReadTtsState()
    if (action == "help") {
        let out = tgToolCommandJson("tts", "ok")
        out.put("usage", JsonString("/tts status|on|off|provider [name]|limit [chars]|summary|audio <text>"))
        return out.toJsonString()
    }
    if (action == "on" || action == "off") {
        state.put("enabled", (action == "on").toJsonValue())
        tgToolWriteTtsState(state)
        return tgToolTtsStatus(user, state).toJsonString()
    }
    if (action == "provider") {
        if (!value.isEmpty()) {
            state.put("provider", JsonString(value))
            tgToolWriteTtsState(state)
        }
        return tgToolTtsStatus(user, state).toJsonString()
    }
    if (action == "limit") {
        if (!value.isEmpty()) {
            try {
                let limit = max(1, Int64.parse(value))
                state.put("limit", limit.toJsonValue())
                tgToolWriteTtsState(state)
            } catch (_: Exception) {
                return tgToolCommandJson("tts", "usage", ok: false, message: "usage: /tts limit <chars>").toJsonString()
            }
        }
        return tgToolTtsStatus(user, state).toJsonString()
    }
    if (action == "status" || action == "summary") {
        return tgToolTtsStatus(user, state).toJsonString()
    }
    if (action != "audio") {
        return tgToolCommandJson("tts", "usage", ok: false, message: "usage: /tts status|on|off|provider|limit|summary|audio").toJsonString()
    }
    if (value.isEmpty()) {
        return tgToolCommandJson("tts", "usage", ok: false, message: "usage: /tts audio <text>").toJsonString()
    }
    let status = tgToolTtsStatus(user, state)
    let provider = tgToolJsonString(status, "provider")
    if (provider.isEmpty()) {
        return status.toJsonString()
    }
    let enabled = match (status.get("enabled")) {
        case Some(v) => try { v.asBool().getValue() } catch (_: Exception) { true }
        case None => true
    }
    if (!enabled) {
        return tgToolCommandJson("tts", "disabled", ok: false, message: "Telegram native TTS is off.").toJsonString()
    }
    let limit = tgToolJsonInt(status, "limit", 4000)
    if (Int64(value.size) > limit) {
        let out = tgToolCommandJson("tts", "too_large", ok: false, message: "TTS input exceeds configured limit.")
        out.put("limit", limit.toJsonValue())
        return out.toJsonString()
    }
    if (provider != "fake") {
        let out = tgToolCommandJson("tts", "not_found", ok: false, message: "Configured TTS provider '${provider}' is not available in this Gateway build.")
        out.put("provider", JsonString(provider))
        return out.toJsonString()
    }
    let audioPath = tgToolWriteFakeAudio(value)
    "[voice]\nfileId=${audioPath.toString()}\ncaption=TTS (${provider})"
}
