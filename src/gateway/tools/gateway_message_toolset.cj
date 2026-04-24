package metis.gateway.tools

import magic.dsl.{tool, toolset}
import magic.prelude.*

import metis.core.{gatewayMessagePayloadPreview, parseGatewayPollParts, renderGatewayAudioText, renderGatewayDeleteText, renderGatewayDocumentText, renderGatewayEditText, renderGatewayPhotoText, renderGatewayPollText, renderGatewayReactionText, renderGatewayTopicCreateText, renderGatewayTopicEditText, renderGatewayVideoNoteText, renderGatewayVideoText, renderGatewayVoiceText}
import metis.core.config.MetisPaths
import metis.io.PrintUtils

import std.fs.{Path, exists}
import std.process.executeWithOutput

import stdx.encoding.json.{JsonBool, JsonObject, JsonString, JsonValue}

@toolset
public class GatewayMessageToolset {
    private func gatewayMessageBinaryCommand(): (String, Option<Path>) {
        match (MetisPaths.projectRoot()) {
            case Some(root) =>
                let devBinary = root.join("target").join("release").join("bin").join("metis")
                if (exists(devBinary)) {
                    return (devBinary.toString(), Some(root))
                }
                return ("metis", Some(root))
            case None => ("metis", None<Path>)
        }
    }

    private func invokeGatewaySend(payload: JsonObject): JsonObject {
        let (command, workDir) = this.gatewayMessageBinaryCommand()
        let args = ["gateway", "call", "channels.send", payload.toJsonString()]
        let (exitCode, stdoutBytes, stderrBytes) = executeWithOutput(command, args, workingDirectory: workDir)
        let stdout = try { String.fromUtf8(stdoutBytes).trimAscii() } catch (_: Exception) { "" }
        let stderr = try { String.fromUtf8(stderrBytes).trimAscii() } catch (_: Exception) { "" }
        if (!stdout.isEmpty()) {
            try {
                let obj = JsonValue.fromStr(stdout).asObject()
                obj.put("exitCode", exitCode.toJsonValue())
                if (!stderr.isEmpty()) {
                    obj.put("stderr", JsonString(stderr))
                }
                return obj
            } catch (_: Exception) {
                ()
            }
        }
        let out = JsonObject()
        out.put("ok", JsonBool(exitCode == 0))
        out.put("exitCode", exitCode.toJsonValue())
        out.put("stdout", JsonString(stdout))
        out.put("stderr", JsonString(stderr))
        return out
    }

    @tool[
        description: "Send one Gateway-backed message through the unified channels.send RPC surface. Supports action=send, reply, thread, reaction, poll, delete, edit, topic-create, topic-edit, photo, document, audio, voice, video, and video-note.",
        parameters: {
            action: "Message action. Supported now: send, reply, thread, reaction, poll, delete, edit, topic-create, topic-edit, photo, document, audio, voice, video, video-note.",
            channel: "Gateway channel id, such as feishu or qq.",
            to: "Target peer/chat id.",
            message: "Message text to send.",
            replyTo: "Reply target message id for action=reply.",
            threadId: "Thread root or anchor message id for action=thread.",
            reaction: "For action=reaction, the reaction token or short text to send, such as +1, thumbs_up, or acknowledged.",
            poll: "For action=poll, a pipe-delimited poll payload such as 'Lunch?|Rice|Noodles|Salad'. It is encoded into a structured text payload."
        }
    ]
    public func message(
        action: String,
        channel: Option<String>,
        to: Option<String>,
        message: Option<String>,
        replyTo: Option<String>,
        threadId: Option<String>,
        reaction: Option<String>,
        poll: Option<String>
    ): String {
        let act = action.trimAscii().toAsciiLower()
        PrintUtils.printTool("message", shortMessage: act)

        if (!(act == "send" || act == "reply" || act == "thread" || act == "reaction" || act == "poll" || act == "delete" || act == "edit" || act == "topic-create" || act == "topic-edit" || act == "photo" || act == "document" || act == "audio" || act == "voice" || act == "video" || act == "video-note")) {
            let unsupported = JsonObject()
            unsupported.put("ok", JsonBool(false))
            unsupported.put("status", JsonString("unsupported"))
            unsupported.put("action", JsonString(act))
            unsupported.put("error", JsonString("Unsupported message action in current gateway implementation: ${act}"))
            let out = unsupported.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        let ch = match (channel) {
            case Some(v) => v.trimAscii().toAsciiLower()
            case None => ""
        }
        let target = match (to) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        var text = match (message) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        var payloadKind = "text"
        if (act == "reaction") {
            payloadKind = "reaction"
            text = match (reaction) {
                case Some(v) =>
                    let t = v.trimAscii()
                    if (t.isEmpty()) { "" } else { renderGatewayReactionText(t) }
                case None => ""
            }
        } else if (act == "poll") {
            payloadKind = "poll"
            text = renderGatewayPollText(match (poll) {
                case Some(v) => v
                case None => ""
            })
        } else if (act == "delete") {
            payloadKind = "delete"
            text = renderGatewayDeleteText()
        } else if (act == "edit") {
            payloadKind = "edit"
            text = renderGatewayEditText(text)
        } else if (act == "topic-create") {
            payloadKind = "topic-create"
            text = renderGatewayTopicCreateText(text)
        } else if (act == "topic-edit") {
            payloadKind = "topic-edit"
            text = renderGatewayTopicEditText(text)
        } else if (act == "photo") {
            payloadKind = "photo"
            text = renderGatewayPhotoText(text)
        } else if (act == "document") {
            payloadKind = "document"
            text = renderGatewayDocumentText(text)
        } else if (act == "audio") {
            payloadKind = "audio"
            text = renderGatewayAudioText(text)
        } else if (act == "voice") {
            payloadKind = "voice"
            text = renderGatewayVoiceText(text)
        } else if (act == "video") {
            payloadKind = "video"
            text = renderGatewayVideoText(text)
        } else if (act == "video-note") {
            payloadKind = "video-note"
            text = renderGatewayVideoNoteText(text)
        } else if (act == "reply" || act == "thread") {
            payloadKind = "threaded-text"
        }
        if (ch.isEmpty() || target.isEmpty() || text.isEmpty()) {
            let err = JsonObject()
            err.put("ok", JsonBool(false))
            err.put("status", JsonString("error"))
            err.put("action", JsonString(act))
            err.put("error", JsonString(if (act == "reaction") {
                "reaction requires channel, to, and reaction"
            } else if (act == "poll") {
                "poll requires channel, to, and poll"
            } else if (act == "delete") {
                "delete requires channel and to"
            } else {
                "${act} requires channel, to, and message"
            }))
            let out = err.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        let replyAnchor = if (act == "reply" || act == "edit" || act == "delete" || act == "topic-edit") {
            match (replyTo) {
                case Some(v) => v.trimAscii()
                case None => ""
            }
        } else if (act == "thread") {
            match (threadId) {
                case Some(v) => v.trimAscii()
                case None => ""
            }
        } else {
            ""
        }
        if ((act == "reply" || act == "thread" || act == "edit" || act == "delete" || act == "topic-edit") && replyAnchor.isEmpty()) {
            let err = JsonObject()
            err.put("ok", JsonBool(false))
            err.put("status", JsonString("error"))
            err.put("action", JsonString(act))
            err.put("error", JsonString(
                if (act == "reply") {
                    "reply requires replyTo"
                } else if (act == "thread") {
                    "thread requires threadId"
                } else if (act == "edit") {
                    "edit requires replyTo"
                } else if (act == "topic-edit") {
                    "topic-edit requires replyTo"
                } else {
                    "delete requires replyTo"
                }
            ))
            let out = err.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        let payload = JsonObject()
        payload.put("id", JsonString(ch))
        payload.put("channel", JsonString(ch))
        payload.put("peerId", JsonString(target))
        payload.put("to", JsonString(target))
        payload.put("text", JsonString(text))
        payload.put("message", JsonString(text))
        if (!replyAnchor.isEmpty()) {
            payload.put("replyTo", JsonString(replyAnchor))
            payload.put("replyToMessageId", JsonString(replyAnchor))
        }
        if (act == "thread") {
            payload.put("replyInThread", JsonBool(true))
        }

        let sent = this.invokeGatewaySend(payload)
        let ok = match (sent.get("ok")) {
            case Some(v) =>
                try { v.asBool().getValue() } catch (_: Exception) { false }
            case None => false
        }
        let result = JsonObject()
        result.put("ok", JsonBool(ok))
        result.put("status", JsonString(if (ok) { "accepted" } else { "error" }))
        result.put("action", JsonString(act))
        result.put("channel", JsonString(ch))
        result.put("to", JsonString(target))
        result.put("message", JsonString(text))
        result.put("payloadKind", JsonString(payloadKind))
        result.put("payloadPreview", JsonString(gatewayMessagePayloadPreview(text)))
        if (!replyAnchor.isEmpty()) {
            if (act == "reply") {
                result.put("replyTo", JsonString(replyAnchor))
            } else {
                result.put("threadId", JsonString(replyAnchor))
            }
        }
        if (act == "reaction") {
            match (reaction) {
                case Some(v) =>
                    let t = v.trimAscii()
                    if (!t.isEmpty()) { result.put("reaction", JsonString(t)) }
                case None => ()
            }
        }
        if (act == "poll") {
            match (poll) {
                case Some(v) =>
                    let t = v.trimAscii()
                    if (!t.isEmpty()) {
                        result.put("poll", JsonString(t))
                        let parsed = parseGatewayPollParts(t)
                        if (!parsed[0].isEmpty()) {
                            result.put("pollTitle", JsonString(parsed[0]))
                        }
                    }
                case None => ()
            }
        }
        result.put("gateway", sent)
        let out = result.toJsonString()
        PrintUtils.printToolResult(out)
        return out
    }
}
