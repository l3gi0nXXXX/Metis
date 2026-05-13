package metis.core.config

import magic.jsonable.*

import std.env.getVariable
import std.collection.{ArrayList, HashMap}
import std.fs.{File, FileInfo, Path, exists}
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString, JsonValue}

private func scopeJsonObject(root: JsonObject, key: String): Option<JsonObject> {
    match (root.get(key)) {
        case Some(value) =>
            try { value.asObject() } catch (_: Exception) { None }
        case None => None
    }
}

private func scopeJsonArray(root: JsonObject, key: String): Option<JsonArray> {
    match (root.get(key)) {
        case Some(value) =>
            try { value.asArray() } catch (_: Exception) { None }
        case None => None
    }
}

private func scopeJsonString(root: JsonObject, key: String): Option<String> {
    match (root.get(key)) {
        case Some(value) =>
            try { Some(value.asString().getValue()) } catch (_: Exception) { None }
        case None => None
    }
}

private func scopeJsonBool(root: JsonObject, key: String): Option<Bool> {
    match (root.get(key)) {
        case Some(value) =>
            try { Some(value.asBool().getValue()) } catch (_: Exception) { None }
        case None => None
    }
}

private func scopeCloneValue(value: JsonValue): JsonValue {
    try {
        JsonValue.fromStr(value.toJsonString())
    } catch (_: Exception) {
        value
    }
}

private func scopeCloneObject(value: JsonObject): JsonObject {
    try {
        JsonValue.fromStr(value.toJsonString()).asObject()
    } catch (_: Exception) {
        JsonObject()
    }
}

private func scopeCloneArray(value: JsonArray): JsonArray {
    try {
        JsonValue.fromStr(value.toJsonString()).asArray()
    } catch (_: Exception) {
        JsonArray([])
    }
}

private func scopeAgents(root: JsonObject): JsonObject {
    match (scopeJsonObject(root, "agents")) {
        case Some(agents) => agents
        case None => JsonObject()
    }
}

private func scopeDefaults(root: JsonObject): JsonObject {
    match (scopeJsonObject(scopeAgents(root), "defaults")) {
        case Some(defaults) => defaults
        case None => JsonObject()
    }
}

private func scopeList(root: JsonObject): JsonArray {
    match (scopeJsonArray(scopeAgents(root), "list")) {
        case Some(list) => list
        case None => JsonArray([])
    }
}

private func scopeDiagnostic(code: String, message: String, agentId!: String = ""): JsonObject {
    let out = JsonObject()
    out.put("code", JsonString(code))
    out.put("message", JsonString(message))
    if (!agentId.trimAscii().isEmpty()) {
        out.put("agentId", JsonString(agentId.trimAscii()))
    }
    out
}

private func scopeAddDiagnostic(diagnostics: JsonArray, code: String, message: String, agentId!: String = ""): Unit {
    diagnostics.add(scopeDiagnostic(code, message, agentId: agentId))
}

private func scopeIsAgentIdRune(ch: Rune): Bool {
    (ch >= r'a' && ch <= r'z') ||
    (ch >= r'0' && ch <= r'9') ||
    ch == r'_' ||
    ch == r'-'
}

private func scopeTrimDashes(raw: String): String {
    var out = raw
    while (out.startsWith("-") && out.size > 0) {
        out = out[1..]
    }
    while (out.endsWith("-") && out.size > 0) {
        out = out[..out.size - 1]
    }
    out
}

private func scopeAppendRune(out: String, ch: Rune): String {
    "${out}${ch}"
}

private func scopeIsInvalidRawId(raw: String, normalized: String): Bool {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return true
    }
    trimmed.toAsciiLower() != normalized
}

private func scopeAgentEntries(root: JsonObject, diagnostics: JsonArray): JsonArray {
    let entries = scopeList(root)
    let out = JsonArray([])
    let seen = HashMap<String, Bool>()
    for (i in 0..entries.size()) {
        let entry = try {
            entries[i].asObject()
        } catch (_: Exception) {
            scopeAddDiagnostic(diagnostics, "invalid-entry", "Agent entry is not an object.")
            continue
        }
        let rawId = scopeJsonString(entry, "id") ?? ""
        let normalized = MetisAgentScope.normalizeAgentId(rawId)
        if (scopeIsInvalidRawId(rawId, normalized)) {
            scopeAddDiagnostic(diagnostics, "invalid-agent-id", "Agent id \"${rawId}\" normalizes to \"${normalized}\".", agentId: normalized)
        }
        if (seen.contains(normalized)) {
            scopeAddDiagnostic(diagnostics, "duplicate-agent-id", "Duplicate agent id \"${normalized}\" ignored after the first entry.", agentId: normalized)
            continue
        }
        seen[normalized] = true
        out.add(entry)
    }
    out
}

private func scopeHasConfiguredAgent(root: JsonObject, agentId: String): Bool {
    let diagnostics = JsonArray([])
    let entries = scopeAgentEntries(root, diagnostics)
    for (i in 0..entries.size()) {
        let entry = try { entries[i].asObject() } catch (_: Exception) { JsonObject() }
        if (MetisAgentScope.normalizeAgentId(scopeJsonString(entry, "id") ?? "") == agentId) {
            return true
        }
    }
    false
}

private func scopeFindAgentEntry(root: JsonObject, agentId: String): Option<JsonObject> {
    let diagnostics = JsonArray([])
    let entries = scopeAgentEntries(root, diagnostics)
    for (i in 0..entries.size()) {
        let entry = try { entries[i].asObject() } catch (_: Exception) { JsonObject() }
        if (MetisAgentScope.normalizeAgentId(scopeJsonString(entry, "id") ?? "") == agentId) {
            return Some(entry)
        }
    }
    None
}

private func scopeDefaultAgentId(root: JsonObject, diagnostics: JsonArray): String {
    let entries = scopeAgentEntries(root, diagnostics)
    if (entries.size() == 0) {
        scopeAddDiagnostic(diagnostics, "general-alias", "No agents.list configured; Metis treats historical general callers as the main default agent.", agentId: "main")
        return "main"
    }
    var firstId = ""
    var defaultId = ""
    var defaultCount = 0
    for (i in 0..entries.size()) {
        let entry = try { entries[i].asObject() } catch (_: Exception) { JsonObject() }
        let id = MetisAgentScope.normalizeAgentId(scopeJsonString(entry, "id") ?? "")
        if (firstId.isEmpty()) {
            firstId = id
        }
        match (scopeJsonBool(entry, "default")) {
            case Some(true) =>
                defaultCount += 1
                if (defaultId.isEmpty()) {
                    defaultId = id
                }
            case _ => ()
        }
    }
    if (defaultCount > 1) {
        scopeAddDiagnostic(diagnostics, "multiple-default-agents", "Multiple agents are marked default=true; using the first default entry.", agentId: defaultId)
    }
    if (!defaultId.isEmpty()) {
        return defaultId
    }
    if (!firstId.isEmpty()) {
        return firstId
    }
    "main"
}

private func scopeRequestedAgentId(root: JsonObject, requested: String, defaultId: String, diagnostics: JsonArray): (String, String) {
    let raw = requested.trimAscii()
    if (raw.isEmpty()) {
        return (defaultId, "default")
    }
    let lowered = raw.toAsciiLower()
    if (lowered == "general" && !scopeHasConfiguredAgent(root, "general")) {
        scopeAddDiagnostic(diagnostics, "general-alias", "Requested historical agent id general; resolving it to the default agent.", agentId: defaultId)
        return (defaultId, "alias")
    }
    let normalized = MetisAgentScope.normalizeAgentId(raw)
    if (scopeIsInvalidRawId(raw, normalized)) {
        scopeAddDiagnostic(diagnostics, "invalid-agent-id", "Requested agent id \"${raw}\" normalizes to \"${normalized}\".", agentId: normalized)
    }
    (normalized, "request")
}

private func scopeHomeDir(): String {
    match (getVariable("HOME")) {
        case Some(value) =>
            let trimmed = value.trimAscii()
            if (!trimmed.isEmpty()) {
                return trimmed
            }
        case None => ()
    }
    getVariable("USERPROFILE").getOrDefault { "." }.trimAscii()
}

private func scopeExpandUserPath(raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed == "~") {
        return scopeHomeDir()
    }
    if (trimmed.startsWith("~/")) {
        return scopeHomeDir() + trimmed[1..]
    }
    trimmed
}

private func scopeNormalizePath(path: Path): Path {
    try {
        path.normalize()
    } catch (_: Exception) {
        path
    }
}

private func scopePathText(path: Path): String {
    scopeNormalizePath(path).toString()
}

private func scopeIsWithinRoot(candidate: Path, root: Path): Bool {
    let rootText = scopePathText(root)
    let candidateText = scopePathText(candidate)
    candidateText == rootText || candidateText.startsWith("${rootText}/")
}

private func scopeResolvedUserPath(
    raw: String,
    fallback: Path,
    baseRoot: Path,
    label: String,
    diagnostics: JsonArray,
    agentId: String,
    boundaryRoot!: Path = baseRoot
): Path {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return scopeNormalizePath(fallback)
    }
    if (trimmed.contains("\u{0}")) {
        scopeAddDiagnostic(diagnostics, "dangerous-path", "${label} contains a null byte; using fallback.", agentId: agentId)
        return scopeNormalizePath(fallback)
    }
    let expanded = scopeExpandUserPath(trimmed)
    let path = Path(expanded)
    let resolved = if (path.isAbsolute()) {
        scopeNormalizePath(path)
    } else {
        scopeNormalizePath(baseRoot.join(expanded))
    }
    if (!path.isAbsolute() && !scopeIsWithinRoot(resolved, boundaryRoot)) {
        scopeAddDiagnostic(diagnostics, "path-escape", "${label} escapes its boundary; using fallback.", agentId: agentId)
        return scopeNormalizePath(fallback)
    }
    let text = scopePathText(resolved)
    if (text == "/" || text == "." || text == "..") {
        scopeAddDiagnostic(diagnostics, "dangerous-path", "${label} resolves to a dangerous root path; using fallback.", agentId: agentId)
        return scopeNormalizePath(fallback)
    }
    resolved
}

private func scopePathsOverlap(left: Path, right: Path): Bool {
    scopeIsWithinRoot(left, right) || scopeIsWithinRoot(right, left)
}

private func scopeIdentityFilePath(workspaceDir: Path): Path {
    workspaceDir.join("IDENTITY.md")
}

private func scopeIsIdentityPlaceholder(value: String): Bool {
    let normalized = value.trimAscii()
        .replace("*", "")
        .replace("_", "")
        .replace("(", "")
        .replace(")", "")
        .toAsciiLower()
    normalized == "pick something you like" ||
        normalized == "ai? robot? familiar? ghost in the machine? something weirder?" ||
        normalized == "how do you come across? sharp? warm? chaotic? calm?" ||
        normalized == "your signature - pick one that feels right" ||
        normalized == "workspace-relative path, http(s) url, or data uri"
}

private func scopeIdentityFileObject(workspaceDir: Path): JsonObject {
    let out = JsonObject()
    let path = scopeIdentityFilePath(workspaceDir)
    if (!exists(path)) {
        return out
    }
    let text = try {
        String.fromUtf8(File.readFrom(path))
    } catch (_: Exception) {
        return out
    }
    for (line in text.split("\n")) {
        let cleaned = line.trimAscii().replace("\r", "")
        let withoutBullet = if (cleaned.startsWith("-")) { cleaned[1..].trimAscii() } else { cleaned }
        let parts = withoutBullet.split(":")
        if (parts.size < 2) {
            continue
        }
        let label = parts[0].replace("*", "").replace("_", "").trimAscii().toAsciiLower()
        let value = String.join(parts[1..parts.size], delimiter: ":").replace("*", "").replace("_", "").trimAscii()
        if (value.isEmpty() || scopeIsIdentityPlaceholder(value)) {
            continue
        }
        if (label == "name" || label == "emoji" || label == "theme" || label == "creature" || label == "vibe" || label == "avatar") {
            out.put(label, JsonString(value))
        }
    }
    out
}

private func scopeAvatarHasUriScheme(value: String): Bool {
    let idx = match (value.indexOf(":")) {
        case Some(v) => v
        case None => return false
    }
    if (idx < 1) {
        return false
    }
    let prefix = value[..idx].toAsciiLower()
    if (prefix.size == 1) {
        return false
    }
    for (ch in prefix.toRuneArray()) {
        let ok = (ch >= r'a' && ch <= r'z') || (ch >= r'0' && ch <= r'9') || ch == r'+' || ch == r'.' || ch == r'-'
        if (!ok) {
            return false
        }
    }
    true
}

private func scopeResolveAvatar(
    raw: String,
    workspaceDir: Path,
    source: String,
    diagnostics: JsonArray,
    agentId: String
): String {
    let value = raw.trimAscii()
    if (value.isEmpty()) {
        return ""
    }
    let low = value.toAsciiLower()
    if (low.startsWith("http://") || low.startsWith("https://") || low.startsWith("data:")) {
        return value
    }
    if (value.startsWith("~") || (scopeAvatarHasUriScheme(value) && !value.contains(":\\"))) {
        scopeAddDiagnostic(diagnostics, "identity-avatar-invalid", "${source}.avatar must be workspace-relative, http(s), or data URI.", agentId: agentId)
        return ""
    }
    let candidate = scopeNormalizePath(workspaceDir.join(value))
    if (!scopeIsWithinRoot(candidate, workspaceDir)) {
        scopeAddDiagnostic(diagnostics, "identity-avatar-escape", "${source}.avatar must stay inside workspaceDir.", agentId: agentId)
        return ""
    }
    candidate.toString()
}

private func scopeIdentity(entryOpt: Option<JsonObject>, workspaceDir: Path, diagnostics: JsonArray, agentId: String): JsonObject {
    let out = JsonObject()
    let fileIdentity = scopeIdentityFileObject(workspaceDir)
    let configIdentity = match (entryOpt) {
        case Some(entry) => scopeJsonObject(entry, "identity") ?? JsonObject()
        case None => JsonObject()
    }
    let fields = ["name", "emoji", "theme", "creature", "vibe", "avatar"]
    for (field in fields) {
        var value = ""
        var source = ""
        match (scopeJsonString(configIdentity, field)) {
            case Some(v) =>
                let trimmed = v.trimAscii()
                if (!trimmed.isEmpty()) {
                    value = trimmed
                    source = "agents.list[].identity.${field}"
                }
            case None => ()
        }
        if (value.isEmpty()) {
            match (scopeJsonString(fileIdentity, field)) {
                case Some(v) =>
                    let trimmed = v.trimAscii()
                    if (!trimmed.isEmpty()) {
                        value = trimmed
                        source = "workspace.IDENTITY.md"
                    }
                case None => ()
            }
        }
        if (value.isEmpty()) {
            continue
        }
        if (field == "avatar") {
            let resolved = scopeResolveAvatar(value, workspaceDir, source, diagnostics, agentId)
            if (resolved.isEmpty()) {
                continue
            }
            out.put(field, JsonString(resolved))
        } else {
            out.put(field, JsonString(value))
        }
        out.put("${field}Source", JsonString(source))
    }
    let identityPath = scopeIdentityFilePath(workspaceDir)
    out.put("identityFilePath", JsonString(identityPath.toString()))
    out.put("identityFileExists", exists(identityPath).toJsonValue())
    out
}

private func scopePolicyArray(value: JsonValue): JsonArray {
    try {
        let raw = value.asArray()
        let out = JsonArray([])
        for (i in 0..raw.size()) {
            try {
                let text = raw[i].asString().getValue().trimAscii()
                if (!text.isEmpty()) {
                    out.add(JsonString(text))
                }
            } catch (_: Exception) {
                ()
            }
        }
        out
    } catch (_: Exception) {
        JsonArray([])
    }
}

private func scopeSourceObject(source: String): JsonObject {
    let out = JsonObject()
    out.put("source", JsonString(source))
    out
}

private func scopeArrayPolicy(entryOpt: Option<JsonObject>, defaults: JsonObject, key: String, label: String): JsonObject {
    let out = JsonObject()
    match (entryOpt) {
        case Some(entry) =>
            match (entry.get(key)) {
                case Some(value) =>
                    out.put("source", JsonString("agents.list[].${key}"))
                    out.put("names", scopePolicyArray(value))
                    return out
                case None => ()
            }
        case None => ()
    }
    match (defaults.get(key)) {
        case Some(value) =>
            out.put("source", JsonString("agents.defaults.${key}"))
            out.put("names", scopePolicyArray(value))
        case None =>
            out.put("source", JsonString("unrestricted"))
            out.put("mode", JsonString("unrestricted-${label}"))
    }
    out
}

private func scopeObjectPolicy(entryOpt: Option<JsonObject>, defaults: JsonObject, key: String, label: String): JsonObject {
    let out = JsonObject()
    match (entryOpt) {
        case Some(entry) =>
            match (scopeJsonObject(entry, key)) {
                case Some(value) =>
                    out.put("source", JsonString("agents.list[].${key}"))
                    out.put("raw", scopeCloneObject(value))
                    return out
                case None => ()
            }
        case None => ()
    }
    match (scopeJsonObject(defaults, key)) {
        case Some(value) =>
            out.put("source", JsonString("agents.defaults.${key}"))
            out.put("raw", scopeCloneObject(value))
        case None =>
            out.put("source", JsonString("unrestricted"))
            out.put("mode", JsonString("unrestricted-${label}"))
    }
    out
}

private func scopeCopyRaw(entryOpt: Option<JsonObject>, defaults: JsonObject, out: JsonObject, key: String): Unit {
    match (entryOpt) {
        case Some(entry) =>
            match (entry.get(key)) {
                case Some(value) =>
                    out.put(key, scopeCloneValue(value))
                    return
                case None => ()
            }
        case None => ()
    }
    match (defaults.get(key)) {
        case Some(value) => out.put(key, scopeCloneValue(value))
        case None => ()
    }
}

private func scopeStringSetting(entryOpt: Option<JsonObject>, defaults: JsonObject, out: JsonObject, key: String): Unit {
    match (entryOpt) {
        case Some(entry) =>
            match (scopeJsonString(entry, key)) {
                case Some(value) =>
                    if (!value.trimAscii().isEmpty()) {
                        out.put(key, JsonString(value.trimAscii()))
                        out.put("${key}Source", JsonString("agents.list[].${key}"))
                        return
                    }
                case None => ()
            }
        case None => ()
    }
    match (scopeJsonString(defaults, key)) {
        case Some(value) =>
            if (!value.trimAscii().isEmpty()) {
                out.put(key, JsonString(value.trimAscii()))
                out.put("${key}Source", JsonString("agents.defaults.${key}"))
            }
        case None => ()
    }
}

private func scopeBoolSetting(entryOpt: Option<JsonObject>, defaults: JsonObject, out: JsonObject, key: String): Unit {
    match (entryOpt) {
        case Some(entry) =>
            match (scopeJsonBool(entry, key)) {
                case Some(value) =>
                    out.put(key, JsonBool(value))
                    out.put("${key}Source", JsonString("agents.list[].${key}"))
                    return
                case None => ()
            }
        case None => ()
    }
    match (scopeJsonBool(defaults, key)) {
        case Some(value) =>
            out.put(key, JsonBool(value))
            out.put("${key}Source", JsonString("agents.defaults.${key}"))
        case None => ()
    }
}

private func scopeCopyRuntimeDefaults(entryOpt: Option<JsonObject>, defaults: JsonObject): JsonObject {
    let out = JsonObject()
    for (key in ["thinkingDefault", "reasoningDefault", "verboseDefault"]) {
        scopeStringSetting(entryOpt, defaults, out, key)
    }
    scopeBoolSetting(entryOpt, defaults, out, "fastModeDefault")
    for (key in ["humanDelay", "heartbeat", "params", "runtime"]) {
        scopeCopyRaw(entryOpt, defaults, out, key)
    }
    out
}

private func scopeModelObject(raw: JsonValue): JsonObject {
    let out = JsonObject()
    try {
        let primary = raw.asString().getValue().trimAscii()
        if (!primary.isEmpty()) {
            out.put("primary", JsonString(primary))
        }
        return out
    } catch (_: Exception) {
        ()
    }
    try {
        raw.asObject()
    } catch (_: Exception) {
        out
    }
}

private func scopeModel(entryOpt: Option<JsonObject>, defaults: JsonObject): JsonObject {
    let out = JsonObject()
    var raw = JsonObject()
    var source = "unconfigured"
    match (entryOpt) {
        case Some(entry) =>
            match (entry.get("model")) {
                case Some(value) =>
                    raw = scopeModelObject(value)
                    source = "agents.list[].model"
                case None => ()
            }
        case None => ()
    }
    if (source == "unconfigured") {
        match (defaults.get("model")) {
            case Some(value) =>
                raw = scopeModelObject(value)
                source = "agents.defaults.model"
            case None => ()
        }
    }
    match (scopeJsonString(raw, "primary")) {
        case Some(primary) =>
            if (!primary.trimAscii().isEmpty()) {
                out.put("primary", JsonString(primary.trimAscii()))
                out.put("modelRef", JsonString(primary.trimAscii()))
                out.put("modelRefSource", JsonString("${source}.primary"))
            }
        case None => ()
    }
    out.put("primarySource", JsonString(source))

    var fallbacksSource = "unconfigured"
    var fallbacks = JsonArray([])
    var fallbacksSet = false
    match (entryOpt) {
        case Some(entry) =>
            match (entry.get("model")) {
                case Some(value) =>
                    let entryModel = scopeModelObject(value)
                    match (scopeJsonArray(entryModel, "fallbacks")) {
                        case Some(arr) =>
                            fallbacks = scopeCloneArray(arr)
                            fallbacksSource = "agents.list[].model.fallbacks"
                            fallbacksSet = true
                        case None => ()
                    }
                case None => ()
            }
        case None => ()
    }
    if (!fallbacksSet) {
        match (scopeJsonArray(scopeModelObject(defaults.get("model").getOrDefault { JsonObject() }), "fallbacks")) {
            case Some(arr) =>
                fallbacks = scopeCloneArray(arr)
                fallbacksSource = "agents.defaults.model.fallbacks"
                fallbacksSet = true
            case None => ()
        }
    }
    if (fallbacksSet) {
        out.put("fallbacks", fallbacks)
        out.put("fallbacksSource", JsonString(fallbacksSource))
        out.put("fallbacksEffectiveSource", JsonString(fallbacksSource))
        out.put("fallbacksExplicitlyDisabled", (fallbacks.size() == 0).toJsonValue())
    } else {
        out.put("fallbacksSource", JsonString(fallbacksSource))
        out.put("fallbacksEffectiveSource", JsonString(fallbacksSource))
        out.put("fallbacksExplicitlyDisabled", false.toJsonValue())
    }
    out.put("raw", scopeCloneObject(raw))
    out
}

private func scopeProviderIdFromModelRef(modelRef: String): String {
    let value = modelRef.trimAscii()
    if (value.isEmpty()) {
        return ""
    }
    match (value.indexOf(":")) {
        case Some(index) =>
            if (index > 0) {
                return value[..index].trimAscii().toAsciiLower()
            }
        case None => ()
    }
    match (value.indexOf("/")) {
        case Some(index) =>
            if (index > 0) {
                return value[..index].trimAscii().toAsciiLower()
            }
        case None => ()
    }
    ""
}

private func scopeProviderConfig(root: JsonObject, providerId: String): JsonObject {
    let models = scopeJsonObject(root, "models") ?? JsonObject()
    let providers = scopeJsonObject(models, "providers") ?? JsonObject()
    scopeJsonObject(providers, providerId) ?? JsonObject()
}

private func scopeProviderSummary(root: JsonObject, modelRef: String): JsonObject {
    let providerId = scopeProviderIdFromModelRef(modelRef)
    let provider = scopeProviderConfig(root, providerId)
    let out = JsonObject()
    out.put("providerId", JsonString(providerId))
    out.put("modelRef", JsonString(modelRef.trimAscii()))
    out.put("configured", (provider.size() > 0).toJsonValue())
    out.put("source", JsonString(if (providerId.isEmpty()) { "unconfigured" } else { "modelRef" }))
    out
}

private func scopeAccountSummary(root: JsonObject, modelRef: String): JsonObject {
    let providerId = scopeProviderIdFromModelRef(modelRef)
    let provider = scopeProviderConfig(root, providerId)
    let apiKey = scopeJsonString(provider, "apiKey").getOrDefault { "" }.trimAscii()
    let baseUrl = scopeJsonString(provider, "baseUrl").getOrDefault { "" }.trimAscii()
    let out = JsonObject()
    out.put("providerId", JsonString(providerId))
    out.put("source", JsonString(if (providerId.isEmpty()) { "unconfigured" } else { "models.providers.${providerId}" }))
    out.put("apiKeyConfigured", (!apiKey.isEmpty()).toJsonValue())
    out.put("baseUrlConfigured", (!baseUrl.isEmpty()).toJsonValue())
    let status = if (providerId.isEmpty()) {
        "unconfigured"
    } else if (provider.size() == 0) {
        "not-configured"
    } else if (!apiKey.isEmpty()) {
        "configured"
    } else {
        "missing-api-key"
    }
    out.put("status", JsonString(status))
    out
}

private func scopeFileIsSymlink(path: Path): Bool {
    try {
        FileInfo(path).isSymbolicLink()
    } catch (_: Exception) {
        false
    }
}

private func scopeAuthProfilesStatus(path: Path, out: JsonObject): String {
    if (!exists(path)) {
        return "missing"
    }
    try {
        let root = JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject()
        let profiles = scopeJsonArray(root, "profiles").getOrDefault { JsonArray([]) }
        out.put("profileCount", profiles.size().toJsonValue())
        "present"
    } catch (_: Exception) {
        "invalid-json"
    }
}

private func scopeAddRisk(risks: JsonArray, code: String): Unit {
    risks.add(JsonString(code))
}

public class MetisAgentScope {
    public static func normalizeAgentId(raw: String): String {
        let lower = raw.trimAscii().toAsciiLower()
        var out = ""
        var lastDash = false
        for (ch in lower.toRuneArray()) {
            if (scopeIsAgentIdRune(ch)) {
                out = scopeAppendRune(out, ch)
                lastDash = false
            } else if (!lastDash) {
                out += "-"
                lastDash = true
            }
            if (out.size >= 64) {
                break
            }
        }
        let trimmed = scopeTrimDashes(out)
        if (trimmed.isEmpty()) {
            return "main"
        }
        if (trimmed.size > 64) {
            return scopeTrimDashes(trimmed[..64])
        }
        trimmed
    }

    public static func resolve(
        root: JsonObject,
        agentId!: String = "",
        homeRoot!: Path = MetisPaths.homeRootReadOnly(),
        defaultWorkspace!: Path = MetisPaths.workspaceRootReadOnly()
    ): JsonObject {
        let diagnostics = JsonArray([])
        let defaultId = scopeDefaultAgentId(root, diagnostics)
        let (id, source) = scopeRequestedAgentId(root, agentId, defaultId, diagnostics)
        let entryOpt = scopeFindAgentEntry(root, id)
        let configured = entryOpt.isSome()
        if (!configured && source == "request") {
            scopeAddDiagnostic(diagnostics, "unknown-agent", "Agent \"${id}\" is not configured; defaults are used without widening skills or tools.", agentId: id)
        }
        let defaults = scopeDefaults(root)
        let stateRoot = homeRoot.join("agents").join(id)
        let fallbackAgentDir = stateRoot.join("agent")
        let agentDirBase = stateRoot
        let agentDir = match (entryOpt) {
            case Some(entry) =>
                scopeResolvedUserPath(
                    scopeJsonString(entry, "agentDir") ?? "",
                    fallbackAgentDir,
                    agentDirBase,
                    "agents.list[].agentDir",
                    diagnostics,
                    id,
                    boundaryRoot: agentDirBase
                )
            case None => fallbackAgentDir
        }
        let defaultWorkspaceConfig = scopeJsonString(defaults, "workspace") ?? ""
        let defaultWorkspaceRoot = scopeResolvedUserPath(
            defaultWorkspaceConfig,
            defaultWorkspace,
            defaultWorkspace,
            "agents.defaults.workspace",
            diagnostics,
            id,
            boundaryRoot: defaultWorkspace
        )
        let fallbackWorkspace = if (id == defaultId) {
            defaultWorkspaceRoot
        } else if (!defaultWorkspaceConfig.trimAscii().isEmpty()) {
            defaultWorkspaceRoot.join(id)
        } else {
            homeRoot.join("workspaces").join(id)
        }
        let workspaceDir = match (entryOpt) {
            case Some(entry) =>
                scopeResolvedUserPath(
                    scopeJsonString(entry, "workspace") ?? "",
                    fallbackWorkspace,
                    defaultWorkspaceRoot,
                    "agents.list[].workspace",
                    diagnostics,
                    id,
                    boundaryRoot: defaultWorkspaceRoot
                )
            case None => fallbackWorkspace
        }
        if (scopePathsOverlap(workspaceDir, agentDir)) {
            scopeAddDiagnostic(diagnostics, "workspace-agentdir-overlap", "workspaceDir and agentDir overlap; keep runtime state outside the workspace.", agentId: id)
        }
        let model = scopeModel(entryOpt, defaults)
        let modelRef = scopeJsonString(model, "modelRef").getOrDefault { "" }.trimAscii()

        let out = JsonObject()
        out.put("agentId", JsonString(id))
        out.put("requestedAgentId", JsonString(agentId.trimAscii()))
        out.put("agentIdSource", JsonString(source))
        out.put("defaultAgentId", JsonString(defaultId))
        out.put("configured", configured.toJsonValue())
        out.put("workspaceDir", JsonString(scopePathText(workspaceDir)))
        out.put("agentDir", JsonString(scopePathText(agentDir)))
        out.put("modelsJsonPath", JsonString(agentDir.join("models.json").toString()))
        out.put("authProfilesPath", JsonString(agentDir.join("auth-profiles.json").toString()))
        out.put("legacyAuthPath", JsonString(agentDir.join("auth.json").toString()))
        out.put("sessionsDir", JsonString(stateRoot.join("sessions").toString()))
        out.put("model", model)
        out.put("modelRef", JsonString(modelRef))
        out.put("modelRefSource", JsonString(scopeJsonString(model, "modelRefSource").getOrDefault { "unconfigured" }))
        out.put("providerSummary", scopeProviderSummary(root, modelRef))
        out.put("accountSummary", scopeAccountSummary(root, modelRef))
        out.put("runtimeDefaults", scopeCopyRuntimeDefaults(entryOpt, defaults))
        out.put("skillsPolicy", scopeArrayPolicy(entryOpt, defaults, "skills", "skills"))
        out.put("toolsPolicy", scopeObjectPolicy(entryOpt, defaults, "tools", "tools"))
        out.put("identityPolicy", scopeObjectPolicy(entryOpt, defaults, "identity", "identity"))
        out.put("identity", scopeIdentity(entryOpt, workspaceDir, diagnostics, id))
        out.put("groupChatPolicy", scopeObjectPolicy(entryOpt, defaults, "groupChat", "groupChat"))
        out.put("subagentsPolicy", scopeObjectPolicy(entryOpt, defaults, "subagents", "subagents"))
        out.put("memorySearchPolicy", scopeObjectPolicy(entryOpt, defaults, "memorySearch", "memorySearch"))
        out.put("sandboxPolicy", scopeObjectPolicy(entryOpt, defaults, "sandbox", "sandbox"))
        let raw = JsonObject()
        for (key in ["identity", "groupChat", "subagents", "memorySearch", "sandbox", "tools", "skills", "humanDelay", "heartbeat", "params", "runtime"]) {
            scopeCopyRaw(entryOpt, defaults, raw, key)
        }
        out.put("raw", raw)
        out.put("diagnostics", diagnostics)
        out
    }

    public static func authProfileDiagnostics(scope: JsonObject): JsonObject {
        let out = JsonObject()
        let risks = JsonArray([])
        let authProfilesPath = scopeJsonString(scope, "authProfilesPath").getOrDefault { "" }.trimAscii()
        let legacyAuthPath = scopeJsonString(scope, "legacyAuthPath").getOrDefault { "" }.trimAscii()
        out.put("authProfilesPath", JsonString(authProfilesPath))
        out.put("legacyAuthPath", JsonString(legacyAuthPath))
        out.put("copyDefaultProfiles", false.toJsonValue())
        out.put("copyRequiresExplicitConfirmation", true.toJsonValue())
        scopeAddRisk(risks, "credential-copy-requires-explicit-confirmation")

        if (authProfilesPath.isEmpty()) {
            out.put("authProfilesStatus", JsonString("missing"))
            scopeAddRisk(risks, "auth-profiles-missing")
        } else {
            let path = Path(authProfilesPath)
            let status = scopeAuthProfilesStatus(path, out)
            out.put("authProfilesStatus", JsonString(status))
            if (status == "missing") {
                scopeAddRisk(risks, "auth-profiles-missing")
            } else if (status == "invalid-json") {
                scopeAddRisk(risks, "auth-profiles-invalid")
            }
            if (scopeFileIsSymlink(path)) {
                out.put("authProfilesSymlink", true.toJsonValue())
                scopeAddRisk(risks, "auth-profiles-symlink")
            } else {
                out.put("authProfilesSymlink", false.toJsonValue())
            }
        }

        if (legacyAuthPath.isEmpty()) {
            out.put("legacyAuthStatus", JsonString("absent"))
        } else {
            let legacyPath = Path(legacyAuthPath)
            if (exists(legacyPath)) {
                out.put("legacyAuthStatus", JsonString("present"))
                scopeAddRisk(risks, "legacy-auth-json")
                if (scopeFileIsSymlink(legacyPath)) {
                    out.put("legacyAuthSymlink", true.toJsonValue())
                    scopeAddRisk(risks, "legacy-auth-symlink")
                } else {
                    out.put("legacyAuthSymlink", false.toJsonValue())
                }
            } else {
                out.put("legacyAuthStatus", JsonString("absent"))
                out.put("legacyAuthSymlink", false.toJsonValue())
            }
        }
        out.put("risks", risks)
        out
    }

    public static func summary(
        root: JsonObject,
        homeRoot!: Path = MetisPaths.homeRootReadOnly(),
        defaultWorkspace!: Path = MetisPaths.workspaceRootReadOnly()
    ): JsonObject {
        let diagnostics = JsonArray([])
        let defaultId = scopeDefaultAgentId(root, diagnostics)
        let entries = scopeAgentEntries(root, diagnostics)
        let rows = JsonArray([])
        if (entries.size() == 0) {
            rows.add(resolve(root, agentId: defaultId, homeRoot: homeRoot, defaultWorkspace: defaultWorkspace))
        } else {
            for (i in 0..entries.size()) {
                let entry = try { entries[i].asObject() } catch (_: Exception) { JsonObject() }
                let id = normalizeAgentId(scopeJsonString(entry, "id") ?? "")
                rows.add(resolve(root, agentId: id, homeRoot: homeRoot, defaultWorkspace: defaultWorkspace))
            }
        }
        let out = JsonObject()
        out.put("defaultAgentId", JsonString(defaultId))
        out.put("agents", rows)
        out.put("diagnostics", diagnostics)
        out
    }
}
