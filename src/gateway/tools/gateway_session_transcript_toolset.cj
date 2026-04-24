package metis.gateway.tools

import magic.dsl.{tool, toolset}
import magic.prelude.*

import metis.core.config.{CliConfig, CliSettingManager}
import metis.core.memory.memorySessionStoreForGatewayUser
import metis.core.plan.Plan
import metis.io.PrintUtils

import std.collection.ArrayList
import std.fs.exists
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

@toolset
public class GatewaySessionTranscriptToolset {
    private func gwStore() {
        memorySessionStoreForGatewayUser(CliSettingManager.readGatewaySettings())
    }

    private func normalizeSessionKinds(kinds: Option<Array<String>>): Array<String> {
        let normalized = ArrayList<String>()
        match (kinds) {
            case Some(items) =>
                for (item in items) {
                    let kind = item.trimAscii().toAsciiLower()
                    if (kind == "main" || kind == "group" || kind == "cron" || kind == "hook" || kind == "node" || kind == "other") {
                        var seen = false
                        for (existing in normalized) {
                            if (existing == kind) {
                                seen = true
                                break
                            }
                        }
                        if (!seen) {
                            normalized.add(kind)
                        }
                    }
                }
            case None => ()
        }
        normalized.toArray()
    }

    private func classifySessionKind(sessionKey: String): String {
        let normalized = sessionKey.trimAscii().toAsciiLower()
        if (normalized.isEmpty()) {
            return "other"
        }
        if (normalized.contains(":group:")) {
            return "group"
        }
        if (normalized.contains(":cron:") || normalized.startsWith("cron:")) {
            return "cron"
        }
        if (normalized.contains(":hook:") || normalized.startsWith("hook:")) {
            return "hook"
        }
        if (normalized.contains(":node:") || normalized.startsWith("node:")) {
            return "node"
        }
        if (normalized == "main" || normalized.endsWith(":main") || normalized.startsWith("main:")) {
            return "main"
        }
        return "other"
    }

    private func kindAllowed(kind: String, allowedKinds: Array<String>): Bool {
        if (allowedKinds.isEmpty()) {
            return true
        }
        for (value in allowedKinds) {
            if (value == kind) {
                return true
            }
        }
        return false
    }

    private func normalizeTranscriptRole(role: Option<String>): String {
        match (role) {
            case Some(x) =>
                let t = x.trimAscii().toAsciiLower()
                if (t == "user" || t == "assistant" || t == "system") {
                    t
                } else {
                    "assistant"
                }
            case None => "assistant"
        }
    }

    private func resolveSessionKeyByLabel(label: String): String {
        let normalizedLabel = label.trimAscii().toAsciiLower()
        if (normalizedLabel.isEmpty()) {
            return ""
        }
        for (sessionKey in this.gwStore().listSessionKeys()) {
            let keyLower = sessionKey.toAsciiLower()
            if (keyLower.contains(":${normalizedLabel}:")) {
                return sessionKey
            }
        }
        ""
    }

    private func countOpenPlanTasks(plan: Plan): Int64 {
        let text = plan.toString().trimAscii()
        if (text.isEmpty()) {
            return 0
        }
        var count: Int64 = 0
        for (line in text.split("\n")) {
            let trimmed = line.trimAscii()
            if (trimmed.startsWith("- [ ] ")) {
                count += 1
            }
        }
        count
    }

    @tool[
        description: "Lists locally persisted gateway sessions using the Metis-compatible sessions_list name. Reads local session storage only.",
        parameters: {
            kinds: "Optional array of allowed kinds: main, group, cron, hook, node, other.",
            limit: "Optional maximum number of sessions to return; minimum 1.",
            activeMinutes: "Optional compatibility filter hint; currently advisory only.",
            messageLimit: "Optional number of recent transcript entries to include per session; clamped to 20."
        }
    ]
    public func sessions_list(
        kinds: Option<Array<String>>,
        limit: Option<Int64>,
        activeMinutes: Option<Int64>,
        messageLimit: Option<Int64>
    ): String {
        PrintUtils.printTool("sessions_list", shortMessage: "gateway-sessions")

        let allowedKinds = this.normalizeSessionKinds(kinds)
        let cappedLimit = if (let Some(v) <- limit) {
            if (v < 1) { 1 } else { v }
        } else {
            Int64.Max
        }
        let transcriptLimit = if (let Some(v) <- messageLimit) {
            if (v < 0) {
                0
            } else if (v > 20) {
                20
            } else {
                v
            }
        } else {
            0
        }

        let st = this.gwStore()
        let sessions = JsonArray([])
        var added: Int64 = 0
        for (sessionKey in st.listSessionKeys()) {
            if (added >= cappedLimit) {
                break
            }
            let kind = this.classifySessionKind(sessionKey)
            if (!this.kindAllowed(kind, allowedKinds)) {
                continue
            }
            let transcriptPath = st.transcriptPath(sessionKey)
            let row = JsonObject()
            row.put("key", JsonString(sessionKey))
            row.put("kind", JsonString(kind))
            row.put("transcriptPath", JsonString(transcriptPath.toString()))
            row.put("exists", exists(transcriptPath).toJsonValue())
            if (transcriptLimit > 0) {
                row.put("recentMessages", JsonString(st.formatHistoryAsText(sessionKey, transcriptLimit)))
            }
            sessions.add(row)
            added += 1
        }

        let result = JsonObject()
        result.put("ok", true.toJsonValue())
        result.put("status", JsonString("ok"))
        result.put("action", JsonString("sessions_list"))
        result.put("path", JsonString(st.sessionsRoot().toString()))
        result.put("sessions", sessions)
        if (let Some(v) <- activeMinutes) {
            if (v > 0) {
                result.put("compatNote", JsonString("activeMinutes=${v} was requested, but local session files do not expose indexed last-active metadata, so no active-time filtering was applied."))
            }
        }

        let out = result.toJsonString()
        PrintUtils.printToolResult(out)
        out
    }

    @tool[
        description: "Returns recent transcript for a gateway sessionKey as labeled lines [user]/[assistant]/[system]. Reads local jsonl only.",
        parameters: {
            sessionKey: "Full session key as shown by sessions_list.",
            maxEntries: "Optional max message rows from end of transcript; default 40."
        }
    ]
    public func sessions_history(sessionKey: String, maxEntries: Option<Int64>): String {
        let sk = sessionKey.trimAscii()
        PrintUtils.printTool("sessions_history", shortMessage: sk)
        if (sk.isEmpty()) {
            let err = JsonObject()
            err.put("ok", false.toJsonValue())
            err.put("status", JsonString("error"))
            err.put("action", JsonString("sessions_history"))
            err.put("error", JsonString("sessionKey must be non-empty"))
            let out = err.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }
        let cap = maxEntries ?? 40
        let text = this.gwStore().formatHistoryAsText(sk, cap)
        let result = JsonObject()
        result.put("ok", true.toJsonValue())
        result.put("status", JsonString("ok"))
        result.put("action", JsonString("sessions_history"))
        result.put("sessionKey", JsonString(sk))
        result.put("maxEntries", cap.toJsonValue())
        result.put("history", JsonString(text))
        let out = result.toJsonString()
        PrintUtils.printToolResult(out)
        out
    }

    @tool[
        description: "Cross-session message injection into a local gateway transcript. Appends to the target session jsonl and does not wait for a remote reply.",
        parameters: {
            sessionKey: "Optional target session key. Provide either sessionKey or label.",
            label: "Optional spawned-session label. Provide either label or sessionKey.",
            message: "Message text to append to the target session.",
            timeoutSeconds: "Optional compatibility timeout hint; acknowledged only."
        }
    ]
    public func sessions_send(
        sessionKey: Option<String>,
        label: Option<String>,
        message: String,
        timeoutSeconds: Option<Int64>
    ): String {
        PrintUtils.printTool("sessions_send", shortMessage: "gateway-sessions")
        let msg = message.trimAscii()
        if (msg.isEmpty()) {
            let err = JsonObject()
            err.put("ok", false.toJsonValue())
            err.put("status", JsonString("error"))
            err.put("action", JsonString("sessions_send"))
            err.put("error", JsonString("message must be non-empty"))
            let out = err.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        let sessionKeyText = match (sessionKey) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let labelText = match (label) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        if (!sessionKeyText.isEmpty() && !labelText.isEmpty()) {
            let err = JsonObject()
            err.put("ok", false.toJsonValue())
            err.put("status", JsonString("error"))
            err.put("action", JsonString("sessions_send"))
            err.put("error", JsonString("Provide either sessionKey or label (not both)."))
            let out = err.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        var resolvedSessionKey = sessionKeyText
        if (resolvedSessionKey.isEmpty() && !labelText.isEmpty()) {
            resolvedSessionKey = this.resolveSessionKeyByLabel(labelText)
            if (resolvedSessionKey.isEmpty()) {
                let err = JsonObject()
                err.put("ok", false.toJsonValue())
                err.put("status", JsonString("error"))
                err.put("action", JsonString("sessions_send"))
                err.put("error", JsonString("No session found with label: ${labelText}"))
                let out = err.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }
        }

        if (resolvedSessionKey.isEmpty()) {
            let err = JsonObject()
            err.put("ok", false.toJsonValue())
            err.put("status", JsonString("error"))
            err.put("action", JsonString("sessions_send"))
            err.put("error", JsonString("Either sessionKey or label is required"))
            let out = err.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        let st = this.gwStore()
        if (!exists(st.transcriptPath(resolvedSessionKey))) {
            let err = JsonObject()
            err.put("ok", false.toJsonValue())
            err.put("status", JsonString("error"))
            err.put("action", JsonString("sessions_send"))
            err.put("sessionKey", JsonString(resolvedSessionKey))
            err.put("error", JsonString("Session not found: ${resolvedSessionKey} (use the full sessionKey from sessions_list)"))
            let out = err.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        st.appendTranscriptEntry(resolvedSessionKey, "user", msg)
        let now = DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000
        let result = JsonObject()
        result.put("ok", true.toJsonValue())
        result.put("action", JsonString("sessions_send"))
        result.put("runId", JsonString("local-${now}"))
        result.put("status", JsonString("completed"))
        result.put("sessionKey", JsonString(resolvedSessionKey))
        result.put("message", JsonString(msg))
        if (let Some(v) <- timeoutSeconds) {
            if (v >= 0) {
                result.put("compatNote", JsonString("timeoutSeconds=${v} was accepted, but sessions_send only appends to the target transcript and does not wait for a remote reply."))
            }
        }
        let out = result.toJsonString()
        PrintUtils.printToolResult(out)
        out
    }

    @tool[
        description: "Lightweight /status-style card for the current local runtime and optional session transcript detail.",
        parameters: {
            sessionKey: "Optional session key to inspect. If provided and the transcript exists locally, the response includes transcriptPath and a recent transcript excerpt.",
            model: "Optional model override hint. Current implementation reports it as a compatibility note and does not mutate session state."
        }
    ]
    public func session_status(sessionKey: Option<String>, model: Option<String>): String {
        PrintUtils.printTool("session_status", shortMessage: "local runtime")

        let st = this.gwStore()
        let result = JsonObject()
        result.put("ok", true.toJsonValue())
        result.put("status", JsonString("ok"))
        result.put("cwd", JsonString(CliConfig.cwd.toString()))
        result.put("language", JsonString(CliConfig.language))
        result.put("model", JsonString(CliConfig.model))
        result.put("todoFile", JsonString(CliConfig.todoFile.toString()))
        result.put("todoFileExists", exists(CliConfig.todoFile).toJsonValue())
        result.put("gatewaySessionsPath", JsonString(st.sessionsRoot().toString()))
        result.put("gatewaySessionCount", st.listSessionKeys().size.toJsonValue())

        let plan = Plan.load()
        result.put("planOpenTaskCount", this.countOpenPlanTasks(plan).toJsonValue())
        let planText = plan.toString().trimAscii()
        if (!planText.isEmpty()) {
            result.put("plan", JsonString(planText))
        }

        match (sessionKey) {
            case Some(v) =>
                let sk = v.trimAscii()
                if (!sk.isEmpty()) {
                    let transcriptPath = st.transcriptPath(sk)
                    result.put("sessionKey", JsonString(sk))
                    result.put("transcriptPath", JsonString(transcriptPath.toString()))
                    result.put("transcriptExists", exists(transcriptPath).toJsonValue())
                    if (exists(transcriptPath)) {
                        result.put("history", JsonString(st.formatHistoryAsText(sk, 20)))
                    }
                }
            case None => ()
        }
        match (model) {
            case Some(v) =>
                let trimmed = v.trimAscii()
                if (!trimmed.isEmpty()) {
                    result.put("compatNote", JsonString("model=${trimmed} was accepted for compatibility, but session_status does not mutate session model state in the local transcript-only runtime."))
                }
            case None => ()
        }
        let out = result.toJsonString()
        PrintUtils.printToolResult(out)
        out
    }
}
