package metis.core.model

import metis.core.config.MetisConfigManager

import std.collection.ArrayList
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString}

public enum ModelVisionSupport {
    | Supported
    | Unsupported
    | Unknown
}

public struct ModelCapabilityDecision {
    public ModelCapabilityDecision(
        public let modelRef: String,
        public let normalizedRef: String,
        public let provider: String,
        public let model: String,
        public let vision: ModelVisionSupport,
        public let reason: String,
        public let source: String
    ) {}
}

public func modelVisionSupportToString(value: ModelVisionSupport): String {
    match (value) {
        case Supported => "supported"
        case Unsupported => "unsupported"
        case Unknown => "unknown"
    }
}

public func modelVisionSupportIsSupported(value: ModelVisionSupport): Bool {
    match (value) {
        case Supported => true
        case _ => false
    }
}

private func capabilityNormalizeRef(modelRef: String): String {
    try {
        return MetisConfigManager.normalizeModelRef(modelRef).trimAscii()
    } catch (_: Exception) {
        modelRef.trimAscii().replace("/", ":")
    }
}

private func capabilityCanonicalRef(modelRef: String): String {
    try {
        return MetisConfigManager.canonicalModelRef(modelRef).trimAscii()
    } catch (_: Exception) {
        modelRef.trimAscii().replace("/", ":")
    }
}

private func capabilityProvider(modelRef: String): String {
    let normalized = capabilityNormalizeRef(modelRef)
    if (let Some(index) <- normalized.indexOf(b':')) {
        return normalized[..index].trimAscii().toAsciiLower()
    }
    ""
}

private func capabilityModel(modelRef: String): String {
    let normalized = capabilityNormalizeRef(modelRef)
    if (let Some(index) <- normalized.indexOf(b':')) {
        return normalized[(index + 1)..].trimAscii()
    }
    normalized.trimAscii()
}

private func capabilityArrayContainsImage(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(value) =>
            try {
                let arr = value.asArray()
                for (item in arr.getItems()) {
                    try {
                        let text = item.asString().getValue().trimAscii().toAsciiLower()
                        if (text == "image" || text == "images" || text == "vision" || text == "image-input") {
                            return true
                        }
                    } catch (_: Exception) {
                        ()
                    }
                }
            } catch (_: Exception) {
                ()
            }
        case None => ()
    }
    false
}

private func capabilityString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(value) => try { value.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func capabilityRefFromEntry(entry: JsonObject): String {
    let direct = capabilityString(entry, "modelRef")
    if (!direct.isEmpty()) {
        return direct
    }
    let provider = capabilityString(entry, "provider")
    let model = capabilityString(entry, "model")
    if (!provider.isEmpty() && !model.isEmpty()) {
        return "${provider}:${model}"
    }
    model
}

private func capabilityKnownDecision(modelRef: String): ModelCapabilityDecision {
    let normalized = capabilityNormalizeRef(modelRef)
    let provider = capabilityProvider(modelRef)
    let model = capabilityModel(modelRef)
    let lowerModel = model.toAsciiLower()
    let sourceRef = capabilityCanonicalRef(modelRef)

    if (
        provider == "deepseek" ||
        lowerModel.startsWith("deepseek-chat") ||
        lowerModel.startsWith("deepseek-v4") ||
        lowerModel.startsWith("deepseek-reasoner")
    ) {
        return ModelCapabilityDecision(
            sourceRef,
            normalized,
            provider,
            model,
            Unsupported,
            "DeepSeek chat models are treated as text-only for image understanding.",
            "built-in-deny"
        )
    }

    if (
        provider == "fake" ||
        (provider == "dashscope" || provider == "qwen") && (lowerModel.contains("vl") || lowerModel.contains("qvq") || lowerModel.contains("omni")) ||
        provider == "openai" && (lowerModel.startsWith("gpt-4o") || lowerModel.startsWith("gpt-4.1") || lowerModel.startsWith("gpt-5")) ||
        provider == "google" && lowerModel.startsWith("gemini") ||
        provider == "maas" && lowerModel.contains("qwen2.5-vl") ||
        provider == "openrouter" && (lowerModel.contains("gpt-4o") || lowerModel.contains("gpt-4.1") || lowerModel.contains("gemini") || lowerModel.contains("qwen-vl"))
    ) {
        return ModelCapabilityDecision(
            sourceRef,
            normalized,
            provider,
            model,
            Supported,
            "Known multimodal model family.",
            "built-in-known-vision"
        )
    }

    ModelCapabilityDecision(
        sourceRef,
        normalized,
        provider,
        model,
        Unknown,
        "model capability is unknown; configure gateway.media.image.models[].capabilities=[\"image\"] or agents.defaults.imageModel with a known vision model",
        "unknown"
    )
}

public func resolveModelImageCapability(modelRef: String): ModelCapabilityDecision {
    capabilityKnownDecision(modelRef)
}

public func resolveModelImageCapabilityFromEntry(entry: JsonObject): ModelCapabilityDecision {
    let ref = capabilityRefFromEntry(entry)
    let base = capabilityKnownDecision(ref)
    if (capabilityArrayContainsImage(entry, "capabilities") || capabilityArrayContainsImage(entry, "input")) {
        return ModelCapabilityDecision(
            base.modelRef,
            base.normalizedRef,
            base.provider,
            base.model,
            Supported,
            "Explicit image capability declared by gateway.media.image model entry.",
            "explicit-config"
        )
    }
    base
}

private func capabilityArray(values: Array<String>): JsonArray {
    let out = JsonArray([])
    for (value in values) {
        out.add(JsonString(value))
    }
    out
}

public func modelCapabilityDecisionToJson(decision: ModelCapabilityDecision): JsonObject {
    let out = JsonObject()
    out.put("modelRef", JsonString(decision.normalizedRef))
    out.put("canonicalRef", JsonString(decision.modelRef))
    out.put("provider", JsonString(decision.provider))
    out.put("model", JsonString(decision.model))
    out.put("capability", JsonString("image"))
    out.put("supported", JsonBool(modelVisionSupportIsSupported(decision.vision)))
    out.put("status", JsonString(match (decision.vision) {
        case Supported => "supported"
        case Unsupported => "unsupported_model"
        case Unknown => "unknown_capability"
    }))
    out.put("source", JsonString(decision.source))
    out.put("reason", JsonString(decision.reason))
    if (!modelVisionSupportIsSupported(decision.vision)) {
        out.put("supportedProviders", capabilityArray(["openai", "qwen", "dashscope", "google", "maas", "openrouter"]))
    }
    out
}

public func gatewayModelSupportsImageInput(modelRef: String): Bool {
    modelVisionSupportIsSupported(resolveModelImageCapability(modelRef).vision)
}

public func gatewayImageCapabilityDecisionJson(modelRef: String): JsonObject {
    modelCapabilityDecisionToJson(resolveModelImageCapability(modelRef))
}
