package metis.core.config

import magic.dsl.jsonable
import magic.jsonable.*
import magic.log.LogUtils

import std.collection.{HashMap, ArrayList, filter, collectArray, map}
import std.convert.*
import std.fs.{File, Path, exists}

import stdx.encoding.json.*

@jsonable
protected class QmdUpdateUserSettings {
    protected var onBoot: Bool = true
    protected var waitForBootSync: Bool = false
    protected var interval: String = "5m"
    protected var intervalMs: Int64 = 300000
    protected var debounceMs: Int64 = 15000
    protected var embedInterval: String = "60m"
    protected var embedIntervalMs: Int64 = 3600000
    protected var commandTimeoutMs: Int64 = 30000
    protected var updateTimeoutMs: Int64 = 120000
    protected var embedTimeoutMs: Int64 = 120000
}

@jsonable
protected class QmdMcporterUserSettings {
    protected var enabled: Bool = false
    protected var serverName: String = "qmd"
    protected var startDaemon: Bool = true
}

@jsonable
protected class QmdLimitsUserSettings {
    protected var maxResults: Int64 = 6
    protected var maxSnippetChars: Int64 = 700
    protected var maxInjectedChars: Int64 = 4000
    protected var timeoutMs: Int64 = 4000
}

@jsonable
protected class QmdPathUserSettings {
    protected var name: String = ""
    protected var path: String = ""
    protected var pattern: String = "**/*.md"
}

@jsonable
protected class QmdSessionsUserSettings {
    protected var enabled: Bool = false
    protected var exportDir: String = ""
    protected var retentionDays: Int64 = 0
}

@jsonable
protected class QmdScopeRuleMatchUserSettings {
    protected var channel: String = ""
    protected var chatType: String = ""
    protected var keyPrefix: String = ""
    protected var rawKeyPrefix: String = ""
}

@jsonable
protected class QmdScopeRuleUserSettings {
    protected var action: String = "allow"
    protected var `match`: QmdScopeRuleMatchUserSettings = QmdScopeRuleMatchUserSettings()
}

@jsonable
protected class QmdScopeUserSettings {
    protected var default: String = "deny"
    protected var rules: Array<QmdScopeRuleUserSettings> = []
}

@jsonable
protected class QmdUserSettings {
    protected var command: String = "qmd"
    protected var searchMode: String = "search"
    protected var searchTool: String = ""
    protected var includeDefaultMemory: Bool = true
    protected var paths: Array<QmdPathUserSettings> = []
    protected var sessions: QmdSessionsUserSettings = QmdSessionsUserSettings()
    protected var update: QmdUpdateUserSettings = QmdUpdateUserSettings()
    protected var limits: QmdLimitsUserSettings = QmdLimitsUserSettings()
    protected var scope: QmdScopeUserSettings = QmdScopeUserSettings()
    protected var mcporter: QmdMcporterUserSettings = QmdMcporterUserSettings()
}

@jsonable
protected class MemoryUserSettings {
    protected var backend: String = "local"
    protected var citations: String = "auto"
    protected var qmd: QmdUserSettings = QmdUserSettings()
}

@jsonable
protected class CliSetting {
    /**
     * The programming language setting for the CLI.
     * Language in [cangjie, general, unknown]
     */
    protected var language: String = "unknown"

    /**
     * The MCP server configurations.
     */
    protected var mcpServers: Option<JsonObject> = None

    /**
     * The chat model to use
     */
    protected var model: String = ""

    /**
     * Fast model for auxiliary tasks in hybrid mode
     */
    protected var fastModel: Option<String> = Some("ark:doubao-1-5-pro-32k-250115")

    /**
     * Fallback models to use when primary model fails
     */
    protected var fallbackModels: Array<String> = [] // Disable fallback models by default
    // ["moonshot:kimi-k2-0905-preview", "zhipuai:glm-4.5"]

    /**
     * Dedicated image-understanding model. This prevents media channels from
     * sending image payloads to the primary chat model when it is text-only.
     */
    protected var imageModel: String = ""

    /**
     * Dedicated image-understanding fallback models.
     */
    protected var imageFallbackModels: Array<String> = []

    /**
     * Temperature agents will use
     */
    protected var temperature: Float64 = 1.0

     /**
     * Default input limit for models
     */
    protected var defaultModelInputLimit: Int64 = 128 * 1024

    /**
     * Default output limit for models
     */
    protected var defaultModelOutputLimit: Int64 = 32 * 1024

    /**
     * Whether to enable data collection for telemetry and analytics
     */
    protected var collectData: Bool = false

    /**
     * Memory provider id for the current memory runtime.
     */
    protected var memoryProvider: String = "local"
    protected var memory: MemoryUserSettings = MemoryUserSettings()

    /**
     * Generic external memory search backend config for qmd-like systems.
     * This backend is search-only; durable-memory orchestration still remains local.
     */
    protected var externalMemoryCommand: String = ""
    protected var externalMemoryArgs: Array<String> = []
    protected var externalMemoryTimeoutMs: Int64 = 5000
    protected var externalMemoryBackendLabel: String = "external-command"
    protected var externalMemoryIndexPathHint: String = ""

    /**
     * Native QMD backend config surface.
     * The full QMD manager/runtime will be wired in follow-up stages.
     */
    protected var qmdCommand: String = "qmd"
    protected var qmdSearchMode: String = "search"
    protected var qmdSearchTool: String = ""
    protected var qmdPaths: Array<String> = []
    protected var qmdSessionsEnabled: Bool = false
    protected var qmdUpdateOnBoot: Bool = true
    protected var qmdUpdateWaitForBootSync: Bool = false
    protected var qmdUpdateIntervalMs: Int64 = 300000
    protected var qmdUpdateEmbedIntervalMs: Int64 = 3600000
    protected var qmdUpdateCommandTimeoutMs: Int64 = 30000
    protected var qmdUpdateUpdateTimeoutMs: Int64 = 120000
    protected var qmdUpdateEmbedTimeoutMs: Int64 = 120000
    protected var qmdScopeDefault: String = "deny"
    protected var qmdMcporterEnabled: Bool = false
    protected var qmdMcporterServerName: String = "qmd"

    /**
     * Number of days to retain log files (default: 7 days)
     */
    protected var logRetentionDays: Int64 = 7

    /**
     * Maximum number of log files to keep (default: 100 files)
     */
    protected var logMaxFiles: Int64 = 100

    /**
     * IM 网关（飞书 / QQ 等）用户配置；可通过 `magic-cli gateway` 子命令修改。
     */
    protected var gateway: GatewayUserSettings = GatewayUserSettings()

    /**
     * Agent Skills（SKILL.md）发现与开关；与 CLI / 网关 P1 共用。
     */
    protected var skills: SkillsUserSettings = SkillsUserSettings()
}

protected class CliSettingManager {
    private static prop settingFilePath: Path {
        get() {
            return MetisConfigManager.configPath()
        }
    }

    private static func loadRootObject(): JsonObject {
        MetisConfigManager.initializeIfMissing()
        match (MetisConfigManager.rawConfig()) {
            case Some(root) => root
            case None => JsonObject()
        }
    }

    private static func rootGetObject(root: JsonObject, key: String): Option<JsonObject> {
        match (root.get(key)) {
            case Some(value) =>
                try {
                    value.asObject()
                } catch (_: Exception) {
                    None
                }
            case None => None
        }
    }

    private static func ensureObject(root: JsonObject, key: String): JsonObject {
        match (rootGetObject(root, key)) {
            case Some(obj) => obj
            case None =>
                let obj = JsonObject()
                root.put(key, obj)
                obj
        }
    }

    private static func cloneJsonObjectShallow(root: JsonObject): JsonObject {
        let out = JsonObject()
        for ((key, value) in root.getFields()) {
            out.put(key, value)
        }
        out
    }

    private static func gatewayJsonScalarAsString(value: JsonValue): Option<String> {
        try {
            return Some(value.asString().getValue())
        } catch (_: Exception) {
            ()
        }
        match (value) {
            case v: JsonInt => Some(v.getValue().toString())
            case v: JsonFloat => Some(v.getValue().toString())
            case _ => None
        }
    }

    private static func gatewayStringArrayCompat(value: JsonValue): Option<JsonArray> {
        try {
            let arr = value.asArray()
            let out = JsonArray([])
            for (item in arr.getItems()) {
                match (gatewayJsonScalarAsString(item)) {
                    case Some(text) => out.add(JsonString(text))
                    case None => out.add(item)
                }
            }
            Some(out)
        } catch (_: Exception) {
            None<JsonArray>
        }
    }

    private static func normalizedModelArray(value: JsonValue): Array<String> {
        let out = ArrayList<String>()
        let seen = ArrayList<String>()
        try {
            let arr = value.asArray()
            for (item in arr.getItems()) {
                try {
                    let normalized = MetisConfigManager.normalizeModelRef(
                        item.asString().getValue()
                    ).trimAscii()
                    if (!normalized.isEmpty() && !seen.contains(normalized)) {
                        seen.add(normalized)
                        out.add(normalized)
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

    private static func normalizeGatewayTelegramCompat(gateway: JsonObject): JsonObject {
        let normalized = cloneJsonObjectShallow(gateway)
        match (rootGetObject(gateway, "telegram")) {
            case Some(telegram) =>
                let normalizedTelegram = cloneJsonObjectShallow(telegram)
                for (key in ["allowFrom", "groupAllowFrom"]) {
                    match (telegram.get(key)) {
                        case Some(value) =>
                            match (gatewayStringArrayCompat(value)) {
                                case Some(arr) => normalizedTelegram.put(key, arr)
                                case None => ()
                            }
                        case None => ()
                    }
                }
                normalized.put("telegram", normalizedTelegram)
            case None => ()
        }
        normalized
    }

    private static func readGatewaySettingsFromConfigValue(
        value: JsonValue,
        fallback: GatewayUserSettings
    ): GatewayUserSettings {
        try {
            return GatewayUserSettings.fromJsonValue(value)
        } catch (initial: Exception) {
            try {
                let gateway = value.asObject()
                let normalized = normalizeGatewayTelegramCompat(gateway)
                return GatewayUserSettings.fromJsonValue(normalized)
            } catch (compat: Exception) {
                LogUtils.error(
                    "Failed to parse gateway settings from metis.json; keeping previous/default gateway settings. " +
                    "initial=${initial.message}; compat=${compat.message}"
                )
            }
        }
        fallback
    }

    protected static func resolvedPrimaryModelForSave(setting: CliSetting, root: JsonObject): String {
        match (rootGetObject(root, "agents")) {
            case Some(agents) =>
                match (rootGetObject(agents, "defaults")) {
                    case Some(defaults) =>
                        match (rootGetObject(defaults, "model")) {
                            case Some(modelObj) =>
                                match (modelObj.get("primary")) {
                                    case Some(value) =>
                                        try {
                                            let primary = MetisConfigManager.normalizeModelRef(
                                                value.asString().getValue()
                                            ).trimAscii()
                                            if (!primary.isEmpty()) {
                                                return primary
                                            }
                                        } catch (_: Exception) {
                                            ()
                                        }
                                    case None => ()
                                }
                            case None => ()
                        }
                    case None => ()
                }
            case None => ()
        }
        MetisConfigManager.normalizeModelRef(setting.model).trimAscii()
    }

    protected static func resolvedMemoryProvider(setting: CliSetting, root!: Option<JsonObject> = None): String {
        let configuredBackend = setting.memory.backend.trimAscii()
        if (!configuredBackend.isEmpty()) {
            return configuredBackend
        }
        match (root) {
            case Some(rootObj) =>
                match (rootGetObject(rootObj, "memory")) {
                    case Some(memoryObj) =>
                        // When the top-level memory block is present, treat it as the
                        // authoritative current config source even if backend is blank.
                        // This prevents stale legacy customSettings.memoryProvider values
                        // from silently re-enabling qmd after the user clears memory.backend.
                        match (memoryObj.get("backend")) {
                            case Some(value) =>
                                try {
                                    let backend = value.asString().getValue().trimAscii()
                                    if (!backend.isEmpty()) {
                                        return backend
                                    }
                                } catch (_: Exception) {
                                    ()
                                }
                                return "local"
                            case None => ()
                        }
                    case None => ()
                }
            case None => ()
        }
        let legacyProvider = setting.memoryProvider.trimAscii()
        if (!legacyProvider.isEmpty()) {
            return legacyProvider
        }
        "local"
    }

    private static func overlayFromConfigRoot(setting: CliSetting, root: JsonObject): CliSetting {
        var merged = setting
        match (rootGetObject(root, "agents")) {
            case Some(agents) =>
                match (rootGetObject(agents, "defaults")) {
                    case Some(defaults) =>
                        match (rootGetObject(defaults, "model")) {
                            case Some(modelObj) =>
                                match (modelObj.get("primary")) {
                                    case Some(primaryValue) =>
                                        try {
                                            let primary = MetisConfigManager.normalizeModelRef(
                                                primaryValue.asString().getValue()
                                            ).trimAscii()
                                            if (!primary.isEmpty()) {
                                                merged.model = primary
                                            }
                                        } catch (_: Exception) {
                                            ()
                                        }
                                    case None => ()
                                }
                            case None => ()
                        }
                        match (rootGetObject(defaults, "imageModel")) {
                            case Some(modelObj) =>
                                match (modelObj.get("primary")) {
                                    case Some(primaryValue) =>
                                        try {
                                            let primary = MetisConfigManager.normalizeModelRef(
                                                primaryValue.asString().getValue()
                                            ).trimAscii()
                                            if (!primary.isEmpty()) {
                                                merged.imageModel = primary
                                            }
                                        } catch (_: Exception) {
                                            ()
                                        }
                                    case None => ()
                                }
                                match (modelObj.get("fallbacks")) {
                                    case Some(fallbacksValue) =>
                                        merged.imageFallbackModels = normalizedModelArray(fallbacksValue)
                                    case None => ()
                                }
                            case None => ()
                        }
                    case None => ()
                }
            case None => ()
        }
        match (root.get("language")) {
            case Some(value) =>
                try {
                    let language = value.asString().getValue().trimAscii().toAsciiLower()
                    if (!language.isEmpty()) {
                        merged.language = language
                    }
                } catch (_: Exception) {
                    ()
                }
            case None => ()
        }
        match (root.get("collectData")) {
            case Some(value) =>
                try {
                    merged.collectData = value.asBool().getValue()
                } catch (_: Exception) {
                    ()
                }
            case None => ()
        }
        match (root.get("fastModel")) {
            case Some(value) =>
                try {
                    let fastModel = MetisConfigManager.normalizeModelRef(
                        value.asString().getValue()
                    ).trimAscii()
                    if (!fastModel.isEmpty()) {
                        merged.fastModel = Some(fastModel)
                    }
                } catch (_: Exception) {
                    ()
                }
            case None => ()
        }
        match (root.get("temperature")) {
            case Some(value) =>
                try {
                    merged.temperature = Float64.parse(value.toJsonString())
                } catch (_: Exception) {
                    ()
                }
            case None => ()
        }
        match (root.get("defaultModelInputLimit")) {
            case Some(value) =>
                try {
                    merged.defaultModelInputLimit = value.asInt().getValue()
                } catch (_: Exception) {
                    ()
                }
            case None => ()
        }
        match (root.get("defaultModelOutputLimit")) {
            case Some(value) =>
                try {
                    merged.defaultModelOutputLimit = value.asInt().getValue()
                } catch (_: Exception) {
                    ()
                }
            case None => ()
        }
        match (root.get("mcpServers")) {
            case Some(value) =>
                try {
                    merged.mcpServers = Some(value.asObject())
                } catch (_: Exception) {
                    ()
                }
            case None => ()
        }
        match (root.get("gateway")) {
            case Some(value) =>
                merged.gateway = readGatewaySettingsFromConfigValue(value, merged.gateway)
            case None => ()
        }
        match (rootGetObject(root, "session")) {
            case Some(sessionObj) =>
                match (sessionObj.get("dmScope")) {
                    case Some(value) =>
                        try {
                            let dmScope = value.asString().getValue().trimAscii()
                            if (!dmScope.isEmpty()) {
                                merged.gateway.session.dmScope = dmScope
                            }
                        } catch (_: Exception) {
                            ()
                        }
                    case None => ()
                }
            case None => ()
        }
        match (root.get("skills")) {
            case Some(value) =>
                try {
                    merged.skills = SkillsUserSettings.fromJsonValue(value)
                } catch (_: Exception) {
                    ()
                }
            case None => ()
        }
        match (root.get("memory")) {
            case Some(value) =>
                try {
                    merged.memory = MemoryUserSettings.fromJsonValue(value)
                } catch (_: Exception) {
                    ()
                }
            case None => ()
        }
        merged
    }

    /**
     * Standard Json does not support comments,
     * we add // as Json comment.
     */
    private static func loadJsonFile(path: Path): String {
        return String.join(
            String.fromUtf8(File.readFrom(path)).split("\n") |>
                filter { line => !line.trimAscii().startsWith("//") } |>
                collectArray,
            delimiter: "\n"
        )
    }

    private static var _setting: Option<CliSetting> = None

    protected static mut prop setting: CliSetting {
        get() {
            if (let Some(value) <- _setting) {
                return value
            }
            let setting = CliSettingManager.load()
            _setting = Some(setting)
            return setting
        }
        set(v) {
            _setting = v
        }
    }

    public static func invalidate(): Unit {
        _setting = None
    }

    /** Parse `30s` / `5m` / `1h` / `2d` or a positive millisecond integer. */
    private static func parseDurationOrMs(raw: String): Option<Int64> {
        let t = raw.trimAscii()
        if (t.isEmpty()) {
            return None<Int64>
        }
        try {
            let n = Int64.parse(t)
            if (n > 0) {
                return Some(n)
            }
        } catch (_: Exception) {
            ()
        }
        let low = t.toAsciiLower()
        if (low.size < 2) {
            return None<Int64>
        }
        let suffix = low[low.size - 1..low.size]
        let numPart = t[0..t.size - 1].trimAscii()
        var mult: Int64 = 0
        if (suffix == "s") {
            mult = 1000
        } else if (suffix == "m") {
            mult = 60 * 1000
        } else if (suffix == "h") {
            mult = 3600 * 1000
        } else if (suffix == "d") {
            mult = 86400 * 1000
        } else {
            return None<Int64>
        }
        try {
            let n = Int64.parse(numPart)
            if (n <= 0) {
                return None<Int64>
            }
            Some(n * mult)
        } catch (_: Exception) {
            None<Int64>
        }
    }

    private static func load(): CliSetting {
        if (!exists(settingFilePath)) {
            LogUtils.info("Setting file not found at ${settingFilePath}")
            return CliSetting()
        }

        try {
            let content = loadJsonFile(settingFilePath)
            let root = JsonValue.fromStr(content).asObject()
            return CliSettingManager.overlayFromConfigRoot(CliSetting(), root)
        } catch (ex: JsonableException) {
            LogUtils.info("Setting file is not a valid JSON object")
        } catch (ex: JsonException) {
            LogUtils.info("Setting file is not a valid JSON object")
        } catch (ex: Exception) {
            LogUtils.error("Failed to load setting file: ${ex}")
        }
        return CliSetting()
    }

    /** 读取当前持久化的网关用户配置（含各渠道开关与凭据字段）。 */
    public static func readGatewaySettings(): GatewayUserSettings {
        setting.gateway
    }

    /** 读取 Skills 总开关（来自 metis.json 中的 legacy settings 区域）。 */
    public static func readSkillsEnabled(): Bool {
        setting.skills.enabled
    }

    /** 写回 Skills 总开关到 metis.json，并立即保存到文件。 */
    public static func writeSkillsEnabled(enabled: Bool): Unit {
        let _ = MetisConfigManager.setSkillsEnabled(enabled)
    }

    /** 写回 `metis.json` 中的 `gateway` 段并保存文件。 */
    public static func writeGatewaySettings(g: GatewayUserSettings): Unit {
        MetisConfigManager.setGatewaySettings(g)
    }

    /**
     * 将已加载的 `metis.json`（含 legacy settings 区域）写入 CliConfig（不触碰 Magic Config、不清理模型缓存）。
     * 供 `gateway` 子命令等无法走 `parseArgsAndSetConfig` 的路径调用；缓存清理在 `metis.gateway.runtime` 中对 CliModelManager 进行。
     */
    public static func applyPersistedFieldsToCliConfig(): Unit {
        let s = setting
        let rawRoot = MetisConfigManager.rawConfig()
        CliConfig.model = MetisConfigManager.normalizeModelRef(s.model)
        CliConfig.imageModel = MetisConfigManager.normalizeModelRef(s.imageModel)
        CliConfig.temperature = s.temperature
        CliConfig.defaultModelInputLimit = s.defaultModelInputLimit
        CliConfig.defaultModelOutputLimit = s.defaultModelOutputLimit
        CliConfig.fallbackModels = s.fallbackModels
        CliConfig.imageFallbackModels = s.imageFallbackModels
        CliConfig.collectData = s.collectData
        CliConfig.language = s.language
        CliConfig.memoryProvider = CliSettingManager.resolvedMemoryProvider(s, root: rawRoot)
        let configuredCitations = s.memory.citations.trimAscii().toAsciiLower()
        CliConfig.memoryCitations = if (
            configuredCitations == "auto" || configuredCitations == "on" || configuredCitations == "off"
        ) {
            configuredCitations
        } else {
            "auto"
        }
        CliConfig.externalMemoryCommand = s.externalMemoryCommand.trimAscii()
        CliConfig.externalMemoryArgs = s.externalMemoryArgs
        CliConfig.externalMemoryTimeoutMs = s.externalMemoryTimeoutMs
        CliConfig.externalMemoryBackendLabel = s.externalMemoryBackendLabel.trimAscii()
        if (CliConfig.externalMemoryBackendLabel.isEmpty()) {
            CliConfig.externalMemoryBackendLabel = "external-command"
        }
        CliConfig.externalMemoryIndexPathHint = s.externalMemoryIndexPathHint.trimAscii()
        let qmdCommand = s.memory.qmd.command.trimAscii()
        CliConfig.qmdCommand = if (!qmdCommand.isEmpty()) {
            qmdCommand
        } else {
            s.qmdCommand.trimAscii()
        }
        if (CliConfig.qmdCommand.isEmpty()) {
            CliConfig.qmdCommand = "qmd"
        }
        let qmdSearchMode = s.memory.qmd.searchMode.trimAscii()
        CliConfig.qmdSearchMode = if (!qmdSearchMode.isEmpty()) {
            qmdSearchMode
        } else {
            s.qmdSearchMode.trimAscii()
        }
        if (CliConfig.qmdSearchMode.isEmpty()) {
            CliConfig.qmdSearchMode = "search"
        }
        let qmdSearchTool = s.memory.qmd.searchTool.trimAscii()
        CliConfig.qmdSearchTool = if (!qmdSearchTool.isEmpty()) {
            qmdSearchTool
        } else {
            s.qmdSearchTool.trimAscii()
        }
        CliConfig.qmdIncludeDefaultMemory = s.memory.qmd.includeDefaultMemory
        let pathNames = ArrayList<String>()
        let pathValues = ArrayList<String>()
        let pathPatterns = ArrayList<String>()
        if (s.memory.qmd.paths.size > 0) {
            for (entry in s.memory.qmd.paths) {
                pathNames.add(entry.name.trimAscii())
                pathValues.add(MetisConfigManager.normalizeConfigPathValue(entry.path))
                let pattern = entry.pattern.trimAscii()
                pathPatterns.add(if (!pattern.isEmpty()) { pattern } else { "**/*.md" })
            }
        } else {
            for (legacyPath in s.qmdPaths) {
                pathNames.add("")
                pathValues.add(MetisConfigManager.normalizeConfigPathValue(legacyPath))
                pathPatterns.add("**/*.md")
            }
        }
        CliConfig.qmdPathNames = pathNames.toArray()
        CliConfig.qmdPaths = pathValues.toArray()
        CliConfig.qmdPathPatterns = pathPatterns.toArray()
        CliConfig.qmdSessionsEnabled = if (s.memory.qmd.sessions.enabled) { true } else { s.qmdSessionsEnabled }
        CliConfig.qmdSessionsExportDir = MetisConfigManager.normalizeConfigPathValue(
            s.memory.qmd.sessions.exportDir
        )
        CliConfig.qmdSessionsRetentionDays = s.memory.qmd.sessions.retentionDays
        CliConfig.qmdUpdateOnBoot = if (s.memory.qmd.update.onBoot) { true } else { s.qmdUpdateOnBoot }
        CliConfig.qmdUpdateWaitForBootSync = if (s.memory.qmd.update.waitForBootSync) { true } else { s.qmdUpdateWaitForBootSync }
        CliConfig.qmdUpdateIntervalMs = if (!s.memory.qmd.update.interval.trimAscii().isEmpty()) {
            CliSettingManager.parseDurationOrMs(s.memory.qmd.update.interval) ?? s.qmdUpdateIntervalMs
        } else if (s.memory.qmd.update.intervalMs > 0) {
            s.memory.qmd.update.intervalMs
        } else {
            s.qmdUpdateIntervalMs
        }
        CliConfig.qmdUpdateDebounceMs = if (s.memory.qmd.update.debounceMs > 0) { s.memory.qmd.update.debounceMs } else { 15000 }
        CliConfig.qmdUpdateEmbedIntervalMs = if (!s.memory.qmd.update.embedInterval.trimAscii().isEmpty()) {
            CliSettingManager.parseDurationOrMs(s.memory.qmd.update.embedInterval) ?? s.qmdUpdateEmbedIntervalMs
        } else if (s.memory.qmd.update.embedIntervalMs > 0) {
            s.memory.qmd.update.embedIntervalMs
        } else {
            s.qmdUpdateEmbedIntervalMs
        }
        CliConfig.qmdUpdateCommandTimeoutMs = if (s.memory.qmd.update.commandTimeoutMs > 0) { s.memory.qmd.update.commandTimeoutMs } else { s.qmdUpdateCommandTimeoutMs }
        CliConfig.qmdUpdateUpdateTimeoutMs = if (s.memory.qmd.update.updateTimeoutMs > 0) { s.memory.qmd.update.updateTimeoutMs } else { s.qmdUpdateUpdateTimeoutMs }
        CliConfig.qmdUpdateEmbedTimeoutMs = if (s.memory.qmd.update.embedTimeoutMs > 0) { s.memory.qmd.update.embedTimeoutMs } else { s.qmdUpdateEmbedTimeoutMs }
        CliConfig.qmdLimitsMaxResults = max(1, s.memory.qmd.limits.maxResults)
        CliConfig.qmdLimitsMaxSnippetChars = max(1, s.memory.qmd.limits.maxSnippetChars)
        CliConfig.qmdLimitsMaxInjectedChars = max(1, s.memory.qmd.limits.maxInjectedChars)
        CliConfig.qmdLimitsTimeoutMs = max(1000, s.memory.qmd.limits.timeoutMs)
        let qmdScopeDefault = s.memory.qmd.scope.default.trimAscii()
        CliConfig.qmdScopeDefault = if (!qmdScopeDefault.isEmpty()) {
            qmdScopeDefault
        } else {
            s.qmdScopeDefault.trimAscii()
        }
        if (CliConfig.qmdScopeDefault.isEmpty()) {
            CliConfig.qmdScopeDefault = "deny"
        }
        let scopeActions = ArrayList<String>()
        let scopeChannels = ArrayList<String>()
        let scopeChatTypes = ArrayList<String>()
        let scopeKeyPrefixes = ArrayList<String>()
        let scopeRawKeyPrefixes = ArrayList<String>()
        for (rule in s.memory.qmd.scope.rules) {
            scopeActions.add(rule.action.trimAscii().toAsciiLower())
            scopeChannels.add(rule.`match`.channel.trimAscii().toAsciiLower())
            scopeChatTypes.add(rule.`match`.chatType.trimAscii().toAsciiLower())
            scopeKeyPrefixes.add(rule.`match`.keyPrefix.trimAscii().toAsciiLower())
            scopeRawKeyPrefixes.add(rule.`match`.rawKeyPrefix.trimAscii().toAsciiLower())
        }
        CliConfig.qmdScopeRuleActions = scopeActions.toArray()
        CliConfig.qmdScopeRuleChannels = scopeChannels.toArray()
        CliConfig.qmdScopeRuleChatTypes = scopeChatTypes.toArray()
        CliConfig.qmdScopeRuleKeyPrefixes = scopeKeyPrefixes.toArray()
        CliConfig.qmdScopeRuleRawKeyPrefixes = scopeRawKeyPrefixes.toArray()
        CliConfig.qmdMcporterEnabled = if (s.memory.qmd.mcporter.enabled) { true } else { s.qmdMcporterEnabled }
        let qmdMcporterServerName = s.memory.qmd.mcporter.serverName.trimAscii()
        CliConfig.qmdMcporterServerName = if (!qmdMcporterServerName.isEmpty()) {
            qmdMcporterServerName
        } else {
            s.qmdMcporterServerName.trimAscii()
        }
        if (CliConfig.qmdMcporterServerName.isEmpty()) {
            CliConfig.qmdMcporterServerName = "qmd"
        }
        CliConfig.qmdMcporterStartDaemon = s.memory.qmd.mcporter.startDaemon
    }
}
