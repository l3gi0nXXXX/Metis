package metis.core

import metis.core.config.{CliSettingManager, GatewayUserSettings}
import metis.core.model.modelCapabilityDecisionToJson

import magic.core.message.Message
import magic.core.model.ChatRequest
import magic.model.ModelManager
import magic.prelude.*

import std.convert.*
import std.fs.{File, Path, exists}
import stdx.encoding.base64.toBase64String
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString}

private var gatewayMediaAsrRunnerOverride: Option<(String, String) -> String> = None<(String, String) -> String>
private var gatewayMediaVisionRunnerOverride: Option<(String, String, String, String, Int64) -> String> = None<(String, String, String, String, Int64) -> String>
private var gatewayMediaVideoRunnerOverride: Option<(String, String, String, Int64) -> String> = None<(String, String, String, Int64) -> String>
private var gatewayMediaDocumentExtractorOverride: Option<(String, String, String, Int64) -> String> = None<(String, String, String, Int64) -> String>

public func setGatewayMediaAsrRunnerForTest(runner: Option<(String, String) -> String>): Unit {
    gatewayMediaAsrRunnerOverride = runner
}

public func setGatewayMediaVisionRunnerForTest(runner: Option<(String, String, String, String, Int64) -> String>): Unit {
    gatewayMediaVisionRunnerOverride = runner
}

public func setGatewayMediaVideoRunnerForTest(runner: Option<(String, String, String, Int64) -> String>): Unit {
    gatewayMediaVideoRunnerOverride = runner
}

public func setGatewayMediaDocumentExtractorForTest(extractor: Option<(String, String, String, Int64) -> String>): Unit {
    gatewayMediaDocumentExtractorOverride = extractor
}

public func gatewayMediaTranscribeAudioPathForRuntime(path: String, mime: String): String {
    let normalizedPath = path.trimAscii()
    if (normalizedPath.isEmpty() || !exists(Path(normalizedPath))) {
        return ""
    }
    match (gatewayMediaAsrRunnerOverride) {
        case Some(runner) => try { runner(normalizedPath, mime.trimAscii().toAsciiLower()).trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func gatewayMediaConfiguredTranscribeAudioPathForRuntime(record: JsonObject, user: GatewayUserSettings, path: String, mime: String, maxBytes: Int64): JsonObject {
    let normalizedPath = path.trimAscii()
    if (normalizedPath.isEmpty() || !exists(Path(normalizedPath))) {
        let out = JsonObject()
        out.put("status", JsonString("unsupported"))
        out.put("message", JsonString("audio input path is missing"))
        return out
    }
    let channel = gatewayMediaRuntimeString(record, "channel").toAsciiLower()
    let config = gatewaySpeechResolveAsrConfig(user, channel: channel)
    let configuredMaxBytes = gatewayMediaRuntimeAsrMaxBytes(record, user, -1)
    if (configuredMaxBytes >= 0) {
        config.put("maxBytes", configuredMaxBytes.toJsonValue())
    }
    let outputRoot = Path(normalizedPath).parent.join(".metis-asr")
    gatewaySpeechAsrTranscribeAudioPath(config, normalizedPath, mime, outputRoot: outputRoot, maxBytes: 0)
}

private func gatewayMediaExtractDocumentPathForRuntime(path: String, mime: String, fileName: String, maxBytes: Int64): String {
    let normalizedPath = path.trimAscii()
    if (normalizedPath.isEmpty() || !exists(Path(normalizedPath))) {
        return ""
    }
    match (gatewayMediaDocumentExtractorOverride) {
        case Some(extractor) => try { extractor(normalizedPath, mime.trimAscii().toAsciiLower(), fileName.trimAscii(), maxBytes).trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func gatewayMediaDescribeImagePathForRuntime(path: String, mime: String, kind: String, prompt: String, maxBytes: Int64): String {
    let normalizedPath = path.trimAscii()
    if (normalizedPath.isEmpty() || !exists(Path(normalizedPath))) {
        return ""
    }
    match (gatewayMediaVisionRunnerOverride) {
        case Some(runner) => try { runner(normalizedPath, mime.trimAscii().toAsciiLower(), kind.trimAscii().toAsciiLower(), prompt, maxBytes).trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func gatewayMediaConfiguredDescribeImagePathForRuntime(record: JsonObject, user: GatewayUserSettings, path: String, mime: String, kind: String, prompt: String, maxBytes: Int64): JsonObject {
    let out = JsonObject()
    let normalizedPath = path.trimAscii()
    if (normalizedPath.isEmpty() || !exists(Path(normalizedPath))) {
        out.put("status", JsonString("unsupported"))
        out.put("error", JsonString("image input path is missing"))
        return out
    }
    let channel = gatewayMediaRuntimeString(record, "channel").toAsciiLower()
    let bytes = File.readFrom(Path(normalizedPath))
    let rejected = JsonArray([])
    let candidates = gatewayImageUnderstandingBuildCandidates(user, channel: channel, rejected: Some(rejected))
    if (candidates.isEmpty()) {
        out.put("status", JsonString("not_configured"))
        out.put("error", JsonString("agents.defaults.imageModel.primary or gateway.media.image.models is not configured with a vision-capable model"))
        out.put("attempts", rejected)
        return out
    }
    let attempts = rejected
    let safeMime = if (mime.trimAscii().startsWith("image/")) { mime.trimAscii() } else { "image/jpeg" }
    let dataUrl = "data:${safeMime};base64,${toBase64String(bytes)}"
    for (candidate in candidates) {
        let limit = if (candidate.maxBytes > 0) {
            candidate.maxBytes
        } else if (maxBytes > 0) {
            maxBytes
        } else {
            10 * 1024 * 1024
        }
        if (limit > 0 && Int64(bytes.size) > limit) {
            out.put("status", JsonString("too_large"))
            out.put("fileBytes", Int64(bytes.size).toJsonValue())
            out.put("limitBytes", limit.toJsonValue())
            out.put("error", JsonString("image exceeds configured maxBytes"))
            return out
        }
        let effectivePrompt = if (!prompt.trimAscii().isEmpty()) {
            prompt.trimAscii()
        } else if (!candidate.prompt.trimAscii().isEmpty()) {
            candidate.prompt.trimAscii()
        } else {
            "Describe this Telegram image clearly and concisely for the current user request."
        }
        try {
            let model = ModelManager.createChatModel(candidate.modelRef)
            let response = model.create(ChatRequest(Message.user(effectivePrompt, image: Some(dataUrl)), temperature: Some(0.0), maxTokens: Some(1024)))
            var content = response.message.content.trimAscii()
            if (!content.isEmpty()) {
                var truncated = false
                if (candidate.maxChars > 0 && Int64(content.size) > candidate.maxChars) {
                    content = content[..candidate.maxChars]
                    truncated = true
                }
                out.put("status", JsonString("ok"))
                out.put("analysis", JsonString(content))
                out.put("provider", JsonString(model.provider))
                out.put("model", JsonString(model.fullName))
                out.put("source", JsonString(candidate.source))
                out.put("truncated", JsonBool(truncated))
                out.put("attempts", attempts)
                return out
            }
            let empty = JsonObject()
            empty.put("model", JsonString(candidate.modelRef))
            empty.put("source", JsonString(candidate.source))
            empty.put("status", JsonString("empty_response"))
            empty.put("capability", modelCapabilityDecisionToJson(candidate.decision).toJsonValue())
            attempts.add(empty)
        } catch (e: Exception) {
            let err = JsonObject()
            err.put("model", JsonString(candidate.modelRef))
            err.put("source", JsonString(candidate.source))
            err.put("status", JsonString("provider_error"))
            err.put("error", JsonString(e.message))
            err.put("capability", modelCapabilityDecisionToJson(candidate.decision).toJsonValue())
            attempts.add(err)
        }
    }
    out.put("status", JsonString("unsupported"))
    out.put("error", JsonString("no configured image understanding model could analyze this image"))
    out.put("attempts", attempts)
    out
}

private func gatewayMediaDescribeVideoPathForRuntime(path: String, mime: String, prompt: String, maxBytes: Int64): String {
    let normalizedPath = path.trimAscii()
    if (normalizedPath.isEmpty() || !exists(Path(normalizedPath))) {
        return ""
    }
    match (gatewayMediaVideoRunnerOverride) {
        case Some(runner) => try { runner(normalizedPath, mime.trimAscii().toAsciiLower(), prompt, maxBytes).trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func gatewayMediaConfiguredDescribeVideoPathForRuntime(record: JsonObject, user: GatewayUserSettings, path: String, mime: String, prompt: String, maxBytes: Int64): JsonObject {
    let normalizedPath = path.trimAscii()
    if (normalizedPath.isEmpty() || !exists(Path(normalizedPath))) {
        let out = JsonObject()
        out.put("status", JsonString("unsupported"))
        out.put("message", JsonString("video input path is missing"))
        return out
    }
    let channel = gatewayMediaRuntimeString(record, "channel").toAsciiLower()
    let config = gatewayMediaResolveVideoConfig(user, channel: channel)
    let outputRoot = Path(normalizedPath).parent.join(".metis-video-understanding")
    gatewayMediaVideoDescribePath(config, normalizedPath, mime, prompt, outputRoot: outputRoot, maxBytes: maxBytes)
}

private func gatewayMediaRuntimeString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func gatewayMediaRuntimeBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
}

private func gatewayMediaRuntimeInt(obj: JsonObject, key: String, fallback: Int64): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            try {
                v.asInt().getValue()
            } catch (_: Exception) {
                try { Int64.parse(v.asString().getValue().trimAscii()) } catch (_inner: Exception) { fallback }
            }
        case None => fallback
    }
}

private func gatewayMediaRuntimeAsrMaxBytes(record: JsonObject, user: GatewayUserSettings, fallback: Int64): Int64 {
    let channel = gatewayMediaRuntimeString(record, "channel").toAsciiLower()
    let channelConfig = match (channel) {
        case "telegram" => user.telegram.speech.asr
        case "feishu" => user.feishu.speech.asr
        case "qq" => user.qq.speech.asr
        case _ => JsonObject()
    }
    let channelLimit = gatewayMediaRuntimeInt(channelConfig, "maxBytes", -1)
    if (channelLimit >= 0) {
        return channelLimit
    }
    gatewayMediaRuntimeInt(user.speech.asr, "maxBytes", fallback)
}

private func gatewayMediaRuntimeSafePreview(pathText: String, maxBytes!: Int64 = 8192): String {
    let path = Path(pathText)
    if (pathText.trimAscii().isEmpty() || !exists(path)) {
        return ""
    }
    let bytes = File.readFrom(path)
    if (bytes.size > maxBytes) {
        return String.fromUtf8(bytes[..maxBytes]).replace("\r\n", "\n").replace("\r", "\n") + "\n[truncated]"
    }
    String.fromUtf8(bytes).replace("\r\n", "\n").replace("\r", "\n")
}

private func gatewayMediaRuntimeReadableTextMime(mime: String, fileName: String): Bool {
    let normalizedMime = mime.trimAscii().toAsciiLower()
    let normalizedName = fileName.trimAscii().toAsciiLower()
    if (normalizedMime.startsWith("text/") || normalizedMime == "application/json" || normalizedMime == "application/xml") {
        return true
    }
    normalizedName.endsWith(".txt") ||
        normalizedName.endsWith(".md") ||
        normalizedName.endsWith(".json") ||
        normalizedName.endsWith(".xml") ||
        normalizedName.endsWith(".csv") ||
        normalizedName.endsWith(".cj") ||
        normalizedName.endsWith(".ts") ||
        normalizedName.endsWith(".js") ||
        normalizedName.endsWith(".py") ||
        normalizedName.endsWith(".log")
}

private func gatewayMediaRuntimeCompanionText(localPath: String, suffixes: Array<String>, maxBytes!: Int64 = 4096): String {
    if (localPath.trimAscii().isEmpty()) {
        return ""
    }
    for (suffix in suffixes) {
        let path = localPath + suffix
        if (exists(Path(path))) {
            return gatewayMediaRuntimeSafePreview(path, maxBytes: maxBytes).trimAscii()
        }
    }
    ""
}

private func gatewayMediaRuntimeIsImageLike(kind: String, mime: String): Bool {
    kind == "photo" || kind == "image" || kind == "sticker" || mime.startsWith("image/")
}

private func gatewayMediaRuntimeIsAudioLike(kind: String, mime: String): Bool {
    kind == "voice" || kind == "audio" || mime.startsWith("audio/")
}

private func gatewayMediaRuntimeIsVideoLike(kind: String, mime: String): Bool {
    kind == "video" || kind == "video-note" || kind == "video_note" || mime.startsWith("video/")
}

private func gatewayMediaRuntimeCapabilityForRecord(kind: String, mime: String): String {
    if (gatewayMediaRuntimeIsAudioLike(kind, mime)) {
        return "audio"
    }
    if (gatewayMediaRuntimeIsVideoLike(kind, mime)) {
        return "video"
    }
    if (gatewayMediaRuntimeIsImageLike(kind, mime)) {
        if (kind == "sticker") {
            return "sticker"
        }
        return "image"
    }
    if (kind == "document" || !mime.isEmpty()) {
        return "document"
    }
    "unknown"
}

private func gatewayMediaRuntimeOutput(kind: String, text: String, source: String, attachmentIndex!: Int64 = 0): JsonObject {
    let out = JsonObject()
    out.put("kind", JsonString(kind))
    out.put("text", JsonString(text))
    out.put("source", JsonString(source))
    out.put("attachmentIndex", attachmentIndex.toJsonValue())
    out
}

private func gatewayMediaRuntimeDecision(capability: String, outcome: String, reason: String): JsonObject {
    let out = JsonObject()
    out.put("capability", JsonString(capability))
    out.put("outcome", JsonString(outcome))
    if (!reason.trimAscii().isEmpty()) {
        out.put("reason", JsonString(reason.trimAscii()))
    }
    out
}

private func gatewayMediaRuntimeResult(
    record: JsonObject,
    capability: String,
    status: String,
    outputs: JsonArray,
    decision: JsonObject,
    error!: String = ""
): JsonObject {
    let out = JsonObject()
    let ok = outputs.size() > 0 || status == "metadata_only"
    out.put("ok", JsonBool(ok))
    out.put("status", JsonString(status))
    out.put("capability", JsonString(capability))
    out.put("mediaId", JsonString(gatewayMediaRuntimeString(record, "mediaId")))
    out.put("mediaKind", JsonString(gatewayMediaRuntimeString(record, "mediaKind")))
    out.put("mimeType", JsonString(gatewayMediaRuntimeString(record, "mimeType")))
    out.put("outputs", outputs)
    out.put("decision", decision)
    if (!error.trimAscii().isEmpty()) {
        out.put("error", JsonString(error.trimAscii()))
    }
    out
}

public func gatewayMediaUnderstandingForRecord(
    record: JsonObject,
    capability!: String = "auto",
    prompt!: String = "",
    maxBytes!: Int64 = 8192
): JsonObject {
    gatewayMediaUnderstandingForRecordWithSettings(record, CliSettingManager.readGatewaySettings(), capability: capability, prompt: prompt, maxBytes: maxBytes)
}

public func gatewayMediaUnderstandingForRecordWithSettings(
    record: JsonObject,
    user: GatewayUserSettings,
    capability!: String = "auto",
    prompt!: String = "",
    maxBytes!: Int64 = 8192
): JsonObject {
    let kind = gatewayMediaRuntimeString(record, "mediaKind").toAsciiLower()
    let mime = gatewayMediaRuntimeString(record, "mimeType").toAsciiLower()
    let fileName = if (!gatewayMediaRuntimeString(record, "fileName").isEmpty()) {
        gatewayMediaRuntimeString(record, "fileName")
    } else {
        gatewayMediaRuntimeString(record, "originalFileName")
    }
    let localPath = gatewayMediaRuntimeString(record, "localPath")
    let downloaded = gatewayMediaRuntimeBool(record, "downloaded")
    let resolvedCapability = if (capability.trimAscii().toAsciiLower() == "auto" || capability.trimAscii().isEmpty()) {
        gatewayMediaRuntimeCapabilityForRecord(kind, mime)
    } else {
        capability.trimAscii().toAsciiLower()
    }
    let outputs = JsonArray([])

    if (!downloaded || localPath.isEmpty() || !exists(Path(localPath))) {
        return gatewayMediaRuntimeResult(
            record,
            resolvedCapability,
            "unsupported",
            outputs,
            gatewayMediaRuntimeDecision(resolvedCapability, "skipped", "media localPath is missing or not downloaded"),
            error: "media localPath is missing or not downloaded"
        )
    }
    let bytes = File.readFrom(Path(localPath))
    if (resolvedCapability != "audio" && resolvedCapability != "video" && maxBytes > 0 && Int64(bytes.size) > maxBytes) {
        let out = gatewayMediaRuntimeResult(
            record,
            resolvedCapability,
            "too_large",
            outputs,
            gatewayMediaRuntimeDecision(resolvedCapability, "rejected", "media exceeds configured maxBytes"),
            error: "media exceeds configured maxBytes"
        )
        out.put("fileBytes", Int64(bytes.size).toJsonValue())
        out.put("limitBytes", maxBytes.toJsonValue())
        return out
    }

    if (resolvedCapability == "audio") {
        if (!gatewayMediaRuntimeIsAudioLike(kind, mime)) {
            return gatewayMediaRuntimeResult(
                record,
                resolvedCapability,
                "unsupported",
                outputs,
                gatewayMediaRuntimeDecision(resolvedCapability, "skipped", "selected media is not audio-like"),
                error: "selected media is not audio-like"
            )
        }
        let recordTranscript = gatewayMediaRuntimeString(record, "transcript")
        let recordAsrTranscript = gatewayMediaRuntimeString(record, "asrTranscript")
        let nativeTranscript = if (recordTranscript.isEmpty() && recordAsrTranscript.isEmpty()) {
            gatewayMediaTranscribeAudioPathForRuntime(localPath, mime)
        } else {
            ""
        }
        let configuredAsr = if (recordTranscript.isEmpty() && recordAsrTranscript.isEmpty() && nativeTranscript.isEmpty()) {
            gatewayMediaConfiguredTranscribeAudioPathForRuntime(record, user, localPath, mime, maxBytes)
        } else {
            JsonObject()
        }
        let configuredStatus = gatewayMediaRuntimeString(configuredAsr, "status")
        let configuredTranscript = gatewayMediaRuntimeString(configuredAsr, "transcript")
        let transcript = if (!recordTranscript.isEmpty()) {
            recordTranscript
        } else if (!recordAsrTranscript.isEmpty()) {
            recordAsrTranscript
        } else if (!nativeTranscript.isEmpty()) {
            nativeTranscript
        } else if (!configuredTranscript.isEmpty()) {
            configuredTranscript
        } else {
            gatewayMediaRuntimeCompanionText(localPath, [".transcript.txt", ".txt", ".transcript"], maxBytes: 4096)
        }
        if (!transcript.isEmpty()) {
            let source = if (!recordTranscript.isEmpty() || !recordAsrTranscript.isEmpty()) {
                "media_record_cache"
            } else if (!nativeTranscript.isEmpty()) {
                "native_asr_runtime"
            } else if (!configuredTranscript.isEmpty()) {
                "gateway_asr_runtime"
            } else {
                "transcript_companion_file"
            }
            outputs.add(gatewayMediaRuntimeOutput("audio.transcription", transcript, source))
            let out = gatewayMediaRuntimeResult(record, resolvedCapability, "ok", outputs, gatewayMediaRuntimeDecision(resolvedCapability, "applied", source))
            out.put("transcript", JsonString(transcript))
            out.put("ASRStatus", JsonString("transcribed"))
            return out
        }
        if (configuredStatus == "provider_error" || configuredStatus == "timeout" || configuredStatus == "too_large" || configuredStatus == "disabled" || configuredStatus == "not_found") {
            let message = gatewayMediaRuntimeString(configuredAsr, "message")
            let out = gatewayMediaRuntimeResult(
                record,
                resolvedCapability,
                configuredStatus,
                outputs,
                gatewayMediaRuntimeDecision(resolvedCapability, configuredStatus, message),
                error: message
            )
            out.put("ASRStatus", JsonString(configuredStatus))
            return out
        }
        let out = gatewayMediaRuntimeResult(
            record,
            resolvedCapability,
            "not_configured",
            outputs,
            gatewayMediaRuntimeDecision(resolvedCapability, "not_configured", "native ASR runtime is not configured"),
            error: "native ASR runtime is not configured and no transcript companion file exists"
        )
        out.put("ASRStatus", JsonString("not_configured"))
        return out
    }

    if (resolvedCapability == "image" || resolvedCapability == "sticker") {
        if (!gatewayMediaRuntimeIsImageLike(kind, mime)) {
            return gatewayMediaRuntimeResult(
                record,
                resolvedCapability,
                "unsupported",
                outputs,
                gatewayMediaRuntimeDecision(resolvedCapability, "skipped", "selected media is not image-like"),
                error: "selected media is not image-like"
            )
        }
        let recordDescription = gatewayMediaRuntimeString(record, "description")
        let recordAnalysis = gatewayMediaRuntimeString(record, "analysis")
        let nativeAnalysis = if (recordAnalysis.isEmpty() && recordDescription.isEmpty()) {
            gatewayMediaDescribeImagePathForRuntime(localPath, mime, kind, prompt, maxBytes)
        } else {
            ""
        }
        let companionAnalysis = if (nativeAnalysis.isEmpty()) {
            gatewayMediaRuntimeCompanionText(localPath, [".analysis.txt", ".vision.txt", ".description.txt"], maxBytes: 4096)
        } else {
            ""
        }
        let configuredAnalysis = if (recordAnalysis.isEmpty() && recordDescription.isEmpty() && nativeAnalysis.isEmpty() && companionAnalysis.isEmpty()) {
            gatewayMediaConfiguredDescribeImagePathForRuntime(record, user, localPath, mime, kind, prompt, maxBytes)
        } else {
            JsonObject()
        }
        let text = if (!recordAnalysis.isEmpty()) {
            recordAnalysis
        } else if (!recordDescription.isEmpty()) {
            recordDescription
        } else if (!nativeAnalysis.isEmpty()) {
            nativeAnalysis
        } else if (!companionAnalysis.isEmpty()) {
            companionAnalysis
        } else {
            gatewayMediaRuntimeString(configuredAnalysis, "analysis")
        }
        if (!text.isEmpty()) {
            let outputKind = if (resolvedCapability == "sticker" || kind == "sticker") { "sticker.description" } else { "image.description" }
            let source = if (!recordAnalysis.isEmpty() || !recordDescription.isEmpty()) {
                "media_record_cache"
            } else if (!nativeAnalysis.isEmpty()) {
                "native_vision_runtime"
            } else if (!companionAnalysis.isEmpty()) {
                "analysis_companion_file"
            } else {
                "gateway_image_understanding_runtime"
            }
            outputs.add(gatewayMediaRuntimeOutput(outputKind, text, source))
            let out = gatewayMediaRuntimeResult(record, resolvedCapability, "ok", outputs, gatewayMediaRuntimeDecision(resolvedCapability, "applied", source))
            out.put("analysis", JsonString(text))
            match (configuredAnalysis.get("provider")) {
                case Some(v) => out.put("provider", v)
                case None => ()
            }
            match (configuredAnalysis.get("model")) {
                case Some(v) => out.put("model", v)
                case None => ()
            }
            match (configuredAnalysis.get("attempts")) {
                case Some(v) => out.put("attempts", v)
                case None => ()
            }
            if (outputKind == "sticker.description") {
                out.put("stickerDescription", JsonString(text))
            } else {
                out.put("imageDescription", JsonString(text))
            }
            return out
        }
        let configuredStatus = gatewayMediaRuntimeString(configuredAnalysis, "status")
        if (!configuredStatus.isEmpty() && configuredStatus != "not_configured") {
            let out = gatewayMediaRuntimeResult(
                record,
                resolvedCapability,
                configuredStatus,
                outputs,
                gatewayMediaRuntimeDecision(resolvedCapability, configuredStatus, gatewayMediaRuntimeString(configuredAnalysis, "error")),
                error: gatewayMediaRuntimeString(configuredAnalysis, "error")
            )
            match (configuredAnalysis.get("attempts")) {
                case Some(v) => out.put("attempts", v)
                case None => ()
            }
            out.put("visionStatus", JsonString(configuredStatus))
            return out
        }
        let out = gatewayMediaRuntimeResult(
            record,
            resolvedCapability,
            "not_configured",
            outputs,
            gatewayMediaRuntimeDecision(resolvedCapability, "not_configured", "vision provider is not configured"),
            error: "vision provider is not configured and no analysis companion file exists"
        )
        out.put("visionStatus", JsonString("not_configured"))
        return out
    }

    if (resolvedCapability == "video") {
        if (!gatewayMediaRuntimeIsVideoLike(kind, mime)) {
            return gatewayMediaRuntimeResult(
                record,
                resolvedCapability,
                "unsupported",
                outputs,
                gatewayMediaRuntimeDecision(resolvedCapability, "skipped", "selected media is not video-like"),
                error: "selected media is not video-like"
            )
        }
        let recordDescription = gatewayMediaRuntimeString(record, "description")
        let recordAnalysis = gatewayMediaRuntimeString(record, "analysis")
        let nativeVideo = if (recordAnalysis.isEmpty() && recordDescription.isEmpty()) {
            gatewayMediaDescribeVideoPathForRuntime(localPath, mime, prompt, maxBytes)
        } else {
            ""
        }
        let configuredVideo = if (recordAnalysis.isEmpty() && recordDescription.isEmpty() && nativeVideo.isEmpty()) {
            gatewayMediaConfiguredDescribeVideoPathForRuntime(record, user, localPath, mime, prompt, maxBytes)
        } else {
            JsonObject()
        }
        let configuredStatus = gatewayMediaRuntimeString(configuredVideo, "status")
        let configuredDescription = gatewayMediaRuntimeString(configuredVideo, "description")
        let companionVideo = if (nativeVideo.isEmpty() && configuredDescription.isEmpty()) {
            gatewayMediaRuntimeCompanionText(localPath, [".video.txt", ".analysis.txt", ".description.txt"], maxBytes: 4096)
        } else {
            ""
        }
        let videoText = if (!recordAnalysis.isEmpty()) {
            recordAnalysis
        } else if (!recordDescription.isEmpty()) {
            recordDescription
        } else if (!nativeVideo.isEmpty()) {
            nativeVideo
        } else if (!configuredDescription.isEmpty()) {
            configuredDescription
        } else {
            companionVideo
        }
        if (!videoText.isEmpty()) {
            let source = if (!recordAnalysis.isEmpty() || !recordDescription.isEmpty()) {
                "media_record_cache"
            } else if (!nativeVideo.isEmpty()) {
                "native_video_runtime"
            } else if (!configuredDescription.isEmpty()) {
                "gateway_video_runtime"
            } else {
                "video_companion_file"
            }
            outputs.add(gatewayMediaRuntimeOutput("video.description", videoText, source))
            let out = gatewayMediaRuntimeResult(record, resolvedCapability, "ok", outputs, gatewayMediaRuntimeDecision(resolvedCapability, "applied", source))
            out.put("videoDescription", JsonString(videoText))
            if (!configuredDescription.isEmpty()) {
                match (configuredVideo.get("provider")) { case Some(v) => out.put("provider", v) case None => () }
                match (configuredVideo.get("providerKind")) { case Some(v) => out.put("providerKind", v) case None => () }
                match (configuredVideo.get("model")) { case Some(v) => out.put("model", v) case None => () }
            }
            return out
        }
        if (configuredStatus == "provider_error" || configuredStatus == "timeout" || configuredStatus == "too_large" || configuredStatus == "disabled" || configuredStatus == "not_found") {
            let message = gatewayMediaRuntimeString(configuredVideo, "message")
            let out = gatewayMediaRuntimeResult(
                record,
                resolvedCapability,
                configuredStatus,
                outputs,
                gatewayMediaRuntimeDecision(resolvedCapability, configuredStatus, message),
                error: message
            )
            out.put("videoUnderstandingStatus", JsonString(configuredStatus))
            match (configuredVideo.get("provider")) { case Some(v) => out.put("provider", v) case None => () }
            match (configuredVideo.get("providerKind")) { case Some(v) => out.put("providerKind", v) case None => () }
            match (configuredVideo.get("fileBytes")) { case Some(v) => out.put("fileBytes", v) case None => () }
            match (configuredVideo.get("base64Bytes")) { case Some(v) => out.put("base64Bytes", v) case None => () }
            match (configuredVideo.get("limitBytes")) { case Some(v) => out.put("limitBytes", v) case None => () }
            match (configuredVideo.get("timeoutMs")) { case Some(v) => out.put("timeoutMs", v) case None => () }
            return out
        }
        let out = gatewayMediaRuntimeResult(
            record,
            resolvedCapability,
            "not_configured",
            outputs,
            gatewayMediaRuntimeDecision(resolvedCapability, "not_configured", "video understanding provider is not configured"),
            error: "video understanding provider is not configured"
        )
        out.put("videoUnderstandingStatus", JsonString("not_configured"))
        return out
    }

    if (resolvedCapability == "document") {
        if (gatewayMediaRuntimeReadableTextMime(mime, fileName)) {
            let content = gatewayMediaRuntimeSafePreview(localPath, maxBytes: maxBytes).trimAscii()
            if (!content.isEmpty()) {
                outputs.add(gatewayMediaRuntimeOutput("document.text", content, "text_file_preview"))
                let out = gatewayMediaRuntimeResult(record, resolvedCapability, "ok", outputs, gatewayMediaRuntimeDecision(resolvedCapability, "applied", "text-like document preview"))
                out.put("documentTextPreview", JsonString(content))
                return out
            }
        }
        let nativeExtracted = gatewayMediaExtractDocumentPathForRuntime(localPath, mime, fileName, maxBytes)
        if (!nativeExtracted.isEmpty()) {
            outputs.add(gatewayMediaRuntimeOutput("document.text", nativeExtracted, "native_document_extractor"))
            let out = gatewayMediaRuntimeResult(record, resolvedCapability, "ok", outputs, gatewayMediaRuntimeDecision(resolvedCapability, "applied", "native document extractor"))
            out.put("documentTextPreview", JsonString(nativeExtracted))
            out.put("documentExtractStatus", JsonString("ok"))
            out.put("extractor", JsonString("native"))
            return out
        }
        let extracted = gatewayMediaRuntimeCompanionText(localPath, [".extract.txt", ".text.txt", ".preview.txt"], maxBytes: maxBytes)
        if (!extracted.isEmpty()) {
            outputs.add(gatewayMediaRuntimeOutput("document.text", extracted, "extract_companion_file"))
            let out = gatewayMediaRuntimeResult(record, resolvedCapability, "ok", outputs, gatewayMediaRuntimeDecision(resolvedCapability, "applied", "extract companion file"))
            out.put("documentTextPreview", JsonString(extracted))
            out.put("documentExtractStatus", JsonString("ok"))
            return out
        }
        let out = gatewayMediaRuntimeResult(
            record,
            resolvedCapability,
            "metadata_only",
            outputs,
            gatewayMediaRuntimeDecision(resolvedCapability, "metadata_only", "document extractor is not configured or media is not text-like")
        )
        out.put("documentExtractStatus", JsonString("metadata_only"))
        return out
    }

    gatewayMediaRuntimeResult(
        record,
        resolvedCapability,
        "unsupported",
        outputs,
        gatewayMediaRuntimeDecision(resolvedCapability, "skipped", "unsupported media capability"),
        error: "unsupported media capability"
    )
}

public func gatewayMediaUnderstandingOutputs(result: JsonObject): JsonArray {
    match (result.get("outputs")) {
        case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

public func gatewayMediaUnderstandingFirstText(result: JsonObject): String {
    let outputs = gatewayMediaUnderstandingOutputs(result)
    if (outputs.size() <= 0) {
        return ""
    }
    let first = try { outputs[0].asObject() } catch (_e: Exception) { JsonObject() }
    gatewayMediaRuntimeString(first, "text")
}
