package metis.core

import metis.core.config.{CliConfig, GatewayUserSettings}
import metis.core.model.{ModelCapabilityDecision, modelCapabilityDecisionToJson, modelVisionSupportIsSupported, modelVisionSupportToString, resolveModelImageCapability, resolveModelImageCapabilityFromEntry}

import magic.jsonable.*
import std.collection.ArrayList
import std.convert.Parsable
import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject, JsonString, JsonValue}

public struct GatewayImageUnderstandingCandidate {
    public GatewayImageUnderstandingCandidate(
        public let modelRef: String,
        public let source: String,
        public let prompt: String,
        public let maxBytes: Int64,
        public let maxChars: Int64,
        public let timeoutSeconds: Int64,
        public let decision: ModelCapabilityDecision,
        public let entry: JsonObject
    ) {}
}

private func imageUnderstandingCloneValue(value: JsonValue): JsonValue {
    try {
        JsonValue.fromStr(value.toJsonString())
    } catch (_: Exception) {
        value
    }
}

private func imageUnderstandingCloneObject(obj: JsonObject): JsonObject {
    try {
        JsonValue.fromStr(obj.toJsonString()).asObject()
    } catch (_: Exception) {
        JsonObject()
    }
}

private func imageUnderstandingReadObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) => try { v.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func imageUnderstandingReadArray(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(v) => try { v.asArray() } catch (_: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func imageUnderstandingReadString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func imageUnderstandingReadBool(obj: JsonObject, key: String, fallback: Bool): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_: Exception) { fallback }
        case None => fallback
    }
}

private func imageUnderstandingReadInt(obj: JsonObject, key: String, fallback: Int64): Int64 {
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

private func imageUnderstandingHasMeaningfulConfig(config: JsonObject): Bool {
    if (!imageUnderstandingReadString(config, "provider").isEmpty()) {
        return true
    }
    if (imageUnderstandingReadObject(config, "providers").size() > 0) {
        return true
    }
    if (imageUnderstandingReadArray(config, "models").size() > 0) {
        return true
    }
    match (config.get("command")) {
        case Some(_) => true
        case None => false
    }
}

private func imageUnderstandingDeepMerge(base: JsonObject, override: JsonObject): JsonObject {
    let out = imageUnderstandingCloneObject(base)
    for ((key, overrideValue) in override.getFields()) {
        match (out.get(key)) {
            case Some(baseValue) =>
                let merged = try {
                    let baseObj = baseValue.asObject()
                    let overrideObj = overrideValue.asObject()
                    imageUnderstandingDeepMerge(baseObj, overrideObj).toJsonValue()
                } catch (_: Exception) {
                    imageUnderstandingCloneValue(overrideValue)
                }
                out.put(key, merged)
            case None =>
                out.put(key, imageUnderstandingCloneValue(overrideValue))
        }
    }
    out
}

private func imageUnderstandingChannelConfig(user: GatewayUserSettings, channel: String): JsonObject {
    let normalized = channel.trimAscii().toAsciiLower()
    var typed = JsonObject()
    match (normalized) {
        case "telegram" => typed = user.telegram.image
        case "feishu" => typed = user.feishu.image
        case "qq" => typed = user.qq.image
        case _ => ()
    }
    if (imageUnderstandingHasMeaningfulConfig(typed)) {
        return typed
    }
    match (user.channelsExtra) {
        case Some(extra) =>
            let channelObj = imageUnderstandingReadObject(extra, normalized)
            imageUnderstandingReadObject(channelObj, "image")
        case None => JsonObject()
    }
}

private func imageUnderstandingPutIfMissingString(obj: JsonObject, key: String, value: String): Unit {
    let normalized = value.trimAscii()
    if (normalized.isEmpty()) {
        return
    }
    if (imageUnderstandingReadString(obj, key).isEmpty()) {
        obj.put(key, JsonString(normalized))
    }
}

private func imageUnderstandingPutIfMissingBool(obj: JsonObject, key: String, value: Bool): Unit {
    if (obj.get(key).isNone()) {
        obj.put(key, JsonBool(value))
    }
}

private func imageUnderstandingPutIfMissingInt(obj: JsonObject, key: String, value: Int64): Unit {
    if (obj.get(key).isNone()) {
        obj.put(key, JsonInt(value))
    }
}

private func imageUnderstandingFinalize(config: JsonObject): JsonObject {
    let out = imageUnderstandingCloneObject(config)
    if (imageUnderstandingReadObject(out, "providers").size() == 0) {
        out.put("providers", JsonObject().toJsonValue())
    }
    if (imageUnderstandingReadArray(out, "models").size() == 0) {
        out.put("models", JsonArray([]))
    }
    imageUnderstandingPutIfMissingBool(out, "enabled", true)
    imageUnderstandingPutIfMissingString(out, "prompt", "Describe this Telegram image clearly and concisely for the current user request.")
    imageUnderstandingPutIfMissingInt(out, "maxBytes", 10 * 1024 * 1024)
    imageUnderstandingPutIfMissingInt(out, "maxChars", 1200)
    imageUnderstandingPutIfMissingInt(out, "timeoutSeconds", 60)
    out.put("legacy", JsonBool(false))
    out
}

private func imageUnderstandingApplyTelegramTransportContext(config: JsonObject, user: GatewayUserSettings, channel: String): JsonObject {
    if (channel.trimAscii().toAsciiLower() != "telegram") {
        return config
    }
    let providers = imageUnderstandingReadObject(config, "providers")
    for ((_, value) in providers.getFields()) {
        try {
            let provider = value.asObject()
            imageUnderstandingPutIfMissingString(provider, "proxy", user.telegram.proxy)
            imageUnderstandingPutIfMissingBool(provider, "envProxyEnabled", user.telegram.network.envProxyEnabled)
            imageUnderstandingPutIfMissingBool(provider, "insecureSkipTlsVerify", user.telegram.network.insecureSkipTlsVerify)
        } catch (_: Exception) {
            ()
        }
    }
    config
}

public func gatewayMediaResolveImageConfig(user: GatewayUserSettings, channel!: String = ""): JsonObject {
    let shared = user.media.image
    let channelConfig = imageUnderstandingChannelConfig(user, channel)
    let hasShared = imageUnderstandingHasMeaningfulConfig(shared)
    let hasChannel = imageUnderstandingHasMeaningfulConfig(channelConfig)
    if (hasShared || hasChannel) {
        return imageUnderstandingApplyTelegramTransportContext(
            imageUnderstandingFinalize(imageUnderstandingDeepMerge(shared, channelConfig)),
            user,
            channel
        )
    }
    imageUnderstandingApplyTelegramTransportContext(imageUnderstandingFinalize(JsonObject()), user, channel)
}

public func gatewayImageUnderstandingResolveConfig(user: GatewayUserSettings, channel!: String = ""): JsonObject {
    gatewayMediaResolveImageConfig(user, channel: channel)
}

private func imageUnderstandingAddCandidate(out: JsonArray, seen: ArrayList<String>, modelRef: String, source: String): Unit {
    let normalized = modelRef.trimAscii()
    if (normalized.isEmpty() || seen.contains(normalized)) {
        return
    }
    seen.add(normalized)
    let row = JsonObject()
    row.put("modelRef", JsonString(normalized))
    row.put("source", JsonString(source))
    row.put("capability", modelCapabilityDecisionToJson(resolveModelImageCapability(normalized)).toJsonValue())
    out.add(row)
}

public func gatewayImageUnderstandingCandidateSummary(user: GatewayUserSettings, channel!: String = ""): JsonArray {
    let out = JsonArray([])
    for (candidate in gatewayImageUnderstandingBuildCandidates(user, channel: channel)) {
        let row = imageUnderstandingCandidateToJson(candidate)
        out.add(row)
    }
    out
}

private func imageUnderstandingCandidateRefFromEntry(entry: JsonObject): String {
    let modelRef = imageUnderstandingReadString(entry, "modelRef")
    if (!modelRef.isEmpty()) {
        return modelRef
    }
    let provider = imageUnderstandingReadString(entry, "provider")
    let model = imageUnderstandingReadString(entry, "model")
    if (!provider.isEmpty() && !model.isEmpty()) {
        return "${provider}:${model}"
    }
    model
}

private func imageUnderstandingCandidatePrompt(config: JsonObject, entry: JsonObject): String {
    let entryPrompt = imageUnderstandingReadString(entry, "prompt")
    if (!entryPrompt.isEmpty()) {
        return entryPrompt
    }
    imageUnderstandingReadString(config, "prompt")
}

private func imageUnderstandingAppendAcceptedCandidate(
    out: ArrayList<GatewayImageUnderstandingCandidate>,
    rejected: JsonArray,
    seenAccepted: ArrayList<String>,
    candidate: GatewayImageUnderstandingCandidate
): Unit {
    if (candidate.modelRef.isEmpty()) {
        return
    }
    if (!modelVisionSupportIsSupported(candidate.decision.vision)) {
        let row = JsonObject()
        row.put("modelRef", JsonString(candidate.modelRef))
        row.put("source", JsonString(candidate.source))
        row.put("status", JsonString(modelVisionSupportToString(candidate.decision.vision)))
        row.put("capability", modelCapabilityDecisionToJson(candidate.decision).toJsonValue())
        rejected.add(row)
        return
    }
    if (!seenAccepted.contains(candidate.modelRef)) {
        seenAccepted.add(candidate.modelRef)
        out.add(candidate)
    }
}

private func imageUnderstandingAppendModelRefCandidate(
    out: ArrayList<GatewayImageUnderstandingCandidate>,
    rejected: JsonArray,
    seenAccepted: ArrayList<String>,
    modelRef: String,
    source: String,
    config: JsonObject
): Unit {
    let normalized = modelRef.trimAscii()
    if (normalized.isEmpty()) {
        return
    }
    let decision = resolveModelImageCapability(normalized)
    imageUnderstandingAppendAcceptedCandidate(
        out,
        rejected,
        seenAccepted,
        GatewayImageUnderstandingCandidate(
            decision.normalizedRef,
            source,
            imageUnderstandingReadString(config, "prompt"),
            imageUnderstandingReadInt(config, "maxBytes", 10 * 1024 * 1024),
            imageUnderstandingReadInt(config, "maxChars", 1200),
            imageUnderstandingReadInt(config, "timeoutSeconds", 60),
            decision,
            JsonObject()
        )
    )
}

public func gatewayImageUnderstandingBuildCandidates(
    user: GatewayUserSettings,
    channel!: String = "",
    rejected!: ?JsonArray = None<JsonArray>
): Array<GatewayImageUnderstandingCandidate> {
    let out = ArrayList<GatewayImageUnderstandingCandidate>()
    let rejectedRows = match (rejected) {
        case Some(v) => v
        case None => JsonArray([])
    }
    let seenAccepted = ArrayList<String>()
    let config = gatewayMediaResolveImageConfig(user, channel: channel)
    if (!imageUnderstandingReadBool(config, "enabled", true)) {
        return out.toArray()
    }

    let models = imageUnderstandingReadArray(config, "models")
    for (entryValue in models.getItems()) {
        try {
            let entry = entryValue.asObject()
            let ref = imageUnderstandingCandidateRefFromEntry(entry)
            if (ref.isEmpty()) {
                continue
            }
            let decision = resolveModelImageCapabilityFromEntry(entry)
            imageUnderstandingAppendAcceptedCandidate(
                out,
                rejectedRows,
                seenAccepted,
                GatewayImageUnderstandingCandidate(
                    decision.normalizedRef,
                    "gateway.media.image.models",
                    imageUnderstandingCandidatePrompt(config, entry),
                    imageUnderstandingReadInt(entry, "maxBytes", imageUnderstandingReadInt(config, "maxBytes", 10 * 1024 * 1024)),
                    imageUnderstandingReadInt(entry, "maxChars", imageUnderstandingReadInt(config, "maxChars", 1200)),
                    imageUnderstandingReadInt(entry, "timeoutSeconds", imageUnderstandingReadInt(config, "timeoutSeconds", 60)),
                    decision,
                    entry
                )
            )
        } catch (_: Exception) {
            ()
        }
    }

    imageUnderstandingAppendModelRefCandidate(out, rejectedRows, seenAccepted, CliConfig.imageModelOrEmpty(), "agents.defaults.imageModel.primary", config)
    for (modelRef in CliConfig.imageFallbackModels) {
        imageUnderstandingAppendModelRefCandidate(out, rejectedRows, seenAccepted, modelRef, "agents.defaults.imageModel.fallbacks", config)
    }
    imageUnderstandingAppendModelRefCandidate(out, rejectedRows, seenAccepted, user.channelModels.get(channel.trimAscii().toAsciiLower()) ?? "", "gateway.channelModels.${channel.trimAscii().toAsciiLower()}", config)
    imageUnderstandingAppendModelRefCandidate(out, rejectedRows, seenAccepted, CliConfig.modelOrEmpty(), "agents.defaults.model.primary", config)
    for (modelRef in CliConfig.fallbackModels) {
        imageUnderstandingAppendModelRefCandidate(out, rejectedRows, seenAccepted, modelRef, "agents.defaults.model.fallbacks", config)
    }
    out.toArray()
}

private func imageUnderstandingCandidateToJson(candidate: GatewayImageUnderstandingCandidate): JsonObject {
    let row = JsonObject()
    row.put("modelRef", JsonString(candidate.modelRef))
    row.put("source", JsonString(candidate.source))
    row.put("prompt", JsonString(candidate.prompt))
    row.put("maxBytes", candidate.maxBytes.toJsonValue())
    row.put("maxChars", candidate.maxChars.toJsonValue())
    row.put("timeoutSeconds", candidate.timeoutSeconds.toJsonValue())
    row.put("capability", modelCapabilityDecisionToJson(candidate.decision).toJsonValue())
    row
}

public func gatewayImageUnderstandingDiagnosticSnapshot(user: GatewayUserSettings, channel!: String = ""): JsonObject {
    let rejected = JsonArray([])
    let candidates = gatewayImageUnderstandingBuildCandidates(user, channel: channel, rejected: Some(rejected))
    let out = JsonObject()
    let rows = JsonArray([])
    for (candidate in candidates) {
        rows.add(imageUnderstandingCandidateToJson(candidate))
    }
    let config = gatewayMediaResolveImageConfig(user, channel: channel)
    out.put("enabled", JsonBool(imageUnderstandingReadBool(config, "enabled", true)))
    out.put("configured", JsonBool(candidates.size > 0))
    out.put("channel", JsonString(channel.trimAscii().toAsciiLower()))
    out.put("candidateCount", candidates.size.toJsonValue())
    out.put("candidates", rows)
    out.put("rejected", rejected)
    out.put("imageModel", JsonString(CliConfig.imageModelOrEmpty()))
    let fallbacks = JsonArray([])
    for (modelRef in CliConfig.imageFallbackModels) {
        fallbacks.add(JsonString(modelRef))
    }
    out.put("imageFallbackModels", fallbacks)
    out.put("primaryCapability", modelCapabilityDecisionToJson(resolveModelImageCapability(CliConfig.modelOrEmpty())).toJsonValue())
    out
}
