package metis.core.model

import magic.core.model.ChatModel
import magic.model.ModelManager

import metis.core.config.{CliConfig, CliModelRuntimeStateManager, MetisConfigManager}

import std.collection.ArrayList
import stdx.encoding.json.{JsonArray, JsonObject}

/**
 * Manage model fallback logic and selection
 * Avoid name confusion with Magic's ModelManager class
 */
protected class CliModelManager {
    private static func syncRuntimeConfig(): Unit {
        CliModelRuntimeStateManager.applyRuntimeStateToCliConfig()
    }

    private static func normalizedRuntimeModelRef(raw: String): String {
        let normalized = MetisConfigManager.normalizeModelRef(raw).trimAscii()
        normalized
    }

    private static func canonicalModelRef(raw: String): String {
        MetisConfigManager.canonicalModelRef(raw).trimAscii()
    }

    private static func runtimePrimaryModelRef(): String {
        normalizedRuntimeModelRef(CliConfig.modelOrEmpty())
    }

    private static func requireConfiguredPrimaryModelRef(): String {
        let primary = runtimePrimaryModelRef()
        if (!primary.isEmpty()) {
            return primary
        }
        throw Exception("Primary model is not configured. Set agents.defaults.model.primary in metis.json.")
    }

    private static func runtimeFallbackModelRefs(): Array<String> {
        let out = ArrayList<String>()
        let seen = ArrayList<String>()
        let primaryCanonical = canonicalModelRef(runtimePrimaryModelRef())
        for (raw in CliConfig.fallbackModels) {
            let normalized = normalizedRuntimeModelRef(raw)
            let canonical = canonicalModelRef(normalized)
            if (normalized.isEmpty() || canonical.isEmpty() || canonical == primaryCanonical || seen.contains(canonical)) {
                continue
            }
            seen.add(canonical)
            out.add(normalized)
        }
        out.toArray()
    }

    private static func scopeObject(root: JsonObject, key: String): JsonObject {
        match (root.get(key)) {
            case Some(value) => try { value.asObject() } catch (_: Exception) { JsonObject() }
            case None => JsonObject()
        }
    }

    private static func scopeString(root: JsonObject, key: String): String {
        match (root.get(key)) {
            case Some(value) => try { value.asString().getValue().trimAscii() } catch (_: Exception) { "" }
            case None => ""
        }
    }

    private static func scopeStringArray(root: JsonObject, key: String): Array<String> {
        let arr = match (root.get(key)) {
            case Some(value) => try { value.asArray() } catch (_: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
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
    }

    private static func scopeModel(scope: JsonObject): JsonObject {
        scopeObject(scope, "model")
    }

    private static func scopePrimaryModelRef(scope: JsonObject): String {
        let scoped = scopeString(scope, "modelRef")
        if (!scoped.isEmpty()) {
            return normalizedRuntimeModelRef(scoped)
        }
        let model = scopeModel(scope)
        let modelRef = scopeString(model, "modelRef")
        if (!modelRef.isEmpty()) {
            return normalizedRuntimeModelRef(modelRef)
        }
        normalizedRuntimeModelRef(scopeString(model, "primary"))
    }

    private static func scopeFallbacksConfigured(scope: JsonObject): Bool {
        match (scopeModel(scope).get("fallbacks")) {
            case Some(_) => true
            case None => false
        }
    }

    private static func runtimeFallbackModelRefsForAgentScope(scope: JsonObject): Array<String> {
        if (!scopeFallbacksConfigured(scope)) {
            return runtimeFallbackModelRefs()
        }
        let out = ArrayList<String>()
        let seen = ArrayList<String>()
        let primaryCanonical = canonicalModelRef(scopePrimaryModelRef(scope))
        for (raw in scopeStringArray(scopeModel(scope), "fallbacks")) {
            let normalized = normalizedRuntimeModelRef(raw)
            let canonical = canonicalModelRef(normalized)
            if (normalized.isEmpty() || canonical.isEmpty() || canonical == primaryCanonical || seen.contains(canonical)) {
                continue
            }
            seen.add(canonical)
            out.add(normalized)
        }
        out.toArray()
    }

    public static func modelSelectionSummary(): Array<String> {
        syncRuntimeConfig()
        let out = ArrayList<String>()
        let primary = runtimePrimaryModelRef()
        if (!primary.isEmpty()) {
            out.add(primary)
        }
        for (fallback in runtimeFallbackModelRefs()) {
            out.add(fallback)
        }
        out.toArray()
    }

    public static func modelSelectionSummaryForAgentScope(scope: JsonObject): Array<String> {
        syncRuntimeConfig()
        let primary = scopePrimaryModelRef(scope)
        if (primary.isEmpty()) {
            return modelSelectionSummary()
        }
        let out = ArrayList<String>()
        out.add(primary)
        for (fallback in runtimeFallbackModelRefsForAgentScope(scope)) {
            out.add(fallback)
        }
        out.toArray()
    }

    private static func appendModelCandidate(
        models: ArrayList<ChatModel>,
        seen: ArrayList<String>,
        candidate: ChatModel
    ): Unit {
        let key = canonicalModelRef(candidate.fullName)
        if (key.isEmpty() || seen.contains(key)) {
            return
        }
        seen.add(key)
        models.add(candidate)
    }

    /**
     * Check if an exception should trigger model fallback
     */
    protected static func shouldFallback(ex: Exception): Bool {
        syncRuntimeConfig()
        // Only fallback if we have fallback models configured
        if (runtimeFallbackModelRefs().isEmpty()) {
            return false
        }
        isFallbackError(ex)
    }

    private static func isFallbackError(ex: Exception): Bool {
        let message = ex.message.toAsciiLower()

        // HTTP and model errors that should trigger fallback
        return message.contains("timeout") ||
               message.contains("5") ||  // 5xx server errors
               message.contains("connection") ||
               message.contains("network") ||
               message.contains("429") ||  // Rate limiting
               message.contains("401") ||  // Unauthorized
               message.contains("rate limit") ||
               message.contains("quota") ||
               message.contains("api key") ||
               message.contains("unauthorized") ||
               message.contains("authentication")
    }

    public static func shouldFallbackForAgentScope(ex: Exception, scope: JsonObject): Bool {
        syncRuntimeConfig()
        let primary = scopePrimaryModelRef(scope)
        if (primary.isEmpty()) {
            return shouldFallback(ex)
        }
        if (runtimeFallbackModelRefsForAgentScope(scope).isEmpty()) {
            return false
        }
        isFallbackError(ex)
    }

    private static func buildModel(model: String): ChatModel {
        let m = ModelManager.createChatModel(model)
        m.maxTokens = ModelTokenLimits.getOutputLimit(model)
        return m
    }

    private static var _model: Option<ChatModel> = None

    protected static prop model: ChatModel {
        get() {
            syncRuntimeConfig()
            if (let Some(m) <- _model) {
                return m
            }
            let m = buildModel(requireConfiguredPrimaryModelRef())
            _model = m
            return m
        }
    }

    private static var _fastModel: Option<ChatModel> = None
    protected static prop fastModel: Option<ChatModel> {
        get() {
            syncRuntimeConfig()
            if (let Some(m) <- _fastModel) {
                return m
            }
            if (let Some(m) <- CliConfig.fastModel) {
                let normalized = normalizedRuntimeModelRef(m)
                if (!normalized.isEmpty()) {
                    _fastModel = buildModel(normalized)
                }
            }
            return _fastModel
        }
    }

    private static var _fallbackModels: Array<ChatModel> = []
    private static prop fallbackModels: Array<ChatModel> {
        get() {
            syncRuntimeConfig()
            if (_fallbackModels.isEmpty()) {
                let models = ArrayList<ChatModel>()
                for (model in runtimeFallbackModelRefs()) {
                    models.add(buildModel(model))
                }
                _fallbackModels = models.toArray()
            }
            return _fallbackModels
        }
    }

    // Session-level successful model memory (resets on restart)
    protected static var lastAvailableModel: Option<ChatModel> = None

    /**
     * Reset runtime caches so model changes take effect immediately.
     */
    public static func resetRuntimeState(): Unit {
        syncRuntimeConfig()
        _model = None
        _fastModel = None
        _fallbackModels = []
        lastAvailableModel = None
    }

    protected static func getAllModels(): Array<ChatModel> {
        syncRuntimeConfig()
        let models = ArrayList<ChatModel>()
        let seen = ArrayList<String>()
        if (let Some(model) <- lastAvailableModel) {
            // Use last successful model first
            appendModelCandidate(models, seen, model)
            appendModelCandidate(models, seen, CliModelManager.model)
            for (model in CliModelManager.fallbackModels) {
                appendModelCandidate(models, seen, model)
            }
        } else {
            // First execution, use original order
            appendModelCandidate(models, seen, CliModelManager.model)
            for (model in CliModelManager.fallbackModels) {
                appendModelCandidate(models, seen, model)
            }
        }
        return models.toArray()
    }

    public static func getAllModelsForAgentScope(scope: JsonObject): Array<ChatModel> {
        syncRuntimeConfig()
        let primary = scopePrimaryModelRef(scope)
        if (primary.isEmpty()) {
            return getAllModels()
        }
        let models = ArrayList<ChatModel>()
        let seen = ArrayList<String>()
        appendModelCandidate(models, seen, buildModel(primary))
        for (model in runtimeFallbackModelRefsForAgentScope(scope)) {
            appendModelCandidate(models, seen, buildModel(model))
        }
        models.toArray()
    }
}
