package metis.core.config

import magic.core.model.ChatModel
import magic.model.ModelManager
import magic.log.LogUtils
import magic.config.Config

import std.env.getVariable
import std.fs.*
import std.io.readToEnd
import std.collection.{map, collectArray, ArrayList, filterMap, collectArrayList}
import std.time.DateTime
import std.sort.*

protected class CliConfig {
    /**
     * The version of Magic Cli
     */
    public static const version = "0.1.5"

    private static const AGENTS_FILE_NAME = "AGENTS.md"

    private static var _dotDir: Option<Path> = None
    private static var _cwd: Option<Path> = None
    public static var workspaceDirOverride: String = ""

    /**
     * All generated files are stored under a hidden directory
     */
    public static prop dotDir: Path {
        get() {
            if (let Some(d) <- _dotDir) {
                return d
            }
            let path = MetisPaths.homeRoot()
            _dotDir = path
            path
        }
    }

    public static func invalidatePathCache(): Unit {
        _dotDir = None<Path>
        _cwd = None<Path>
        _subagentDirs = None<ArrayList<Path>>
    }

    /**
     * The current working directory
     */
    public static prop cwd: Path {
        get() {
            if (let Some(d) <- _cwd) {
                return d
            }
            let configured = workspaceDirOverride.trimAscii()
            let path = if (!configured.isEmpty()) {
                Path(configured)
            } else {
                MetisPaths.workspaceRoot()
            }
            if (!exists(path)) {
                Directory.create(path, recursive: true)
            }
            _cwd = path
            path
        }
    }

    /**
     * The logs directory
     */
    public static prop logsDir: Path {
        get() {
            let path = CliConfig.dotDir.join("logs")
            if (!exists(path)) {
                try {
                    Directory.create(path, recursive: true)
                } catch (e: Exception) {
                    // Concurrent gateway run/call processes can race here. If another
                    // process created the directory first, treat that as success.
                    if (!exists(path)) {
                        throw e
                    }
                }
            }
            return path
        }
    }

    /**
     * The log file of Cangjie Magic
     */
    public static prop logFile: Path {
        get() {
            let time = DateTime.now().format("yyyy_MM_dd-HH_mm_ss_SSS")
            CliConfig.logsDir.join("${time}.log")
        }
    }

    /**
     * The plan todo.md file
     * Used by the plan tool
     */
    public static prop todoFile: Path {
        get() {
            CliConfig.dotDir.join("todo.md")
        }
    }

    /**
     * The history file of user inputs
     */
    public static prop readlineFile: Path {
        get() {
            CliConfig.dotDir.join("readline.history")
        }
    }

    /**
     * The user-agent conversation history directory
     */
    public static prop conversationHistoryDir: Path {
        get() {
            CliConfig.dotDir.join("conversation-history")
        }
    }

    /**
     * The archived snapshots for compacted conversations
     */
    public static prop conversationArchiveDir: Path {
        get() {
            let path = CliConfig.dotDir.join("conversation-archives")
            if (!exists(path)) {
                Directory.create(path, recursive: true)
            }
            return path
        }
    }

    /**
     * User Rules Config
     */
    public static prop agentsMarkdownPath: Path {
        get() {
            CliConfig.cwd.join(AGENTS_FILE_NAME)
        }
    }

    /**
     * Whether agent runs autonomously, i.e., tools will be be confirmed by users
     */
    public static var auto: Bool = false

    /**
     * Whether to enable data collection for telemetry and analytics
     * The default value from CliSettingManager will be used.
     */
    public static var collectData: Bool = false

    /**
     * Temperature agents will use
     * The default value from CliSettingManager will be used.
     */
    public static var temperature: Float64 = 0.0

    /**
     * The chat model to use
     */
    public static var _model: Option<String> = None
    public static mut prop model: String {
        get() {
            return _model.getOrThrow()
        }
        set(v) {
            _model = Some(v)
        }
    }

    public static func modelOrEmpty(): String {
        match (_model) {
            case Some(v) => v
            case None => ""
        }
    }

    public static func clearPrimaryModelForTest(): Unit {
        _model = None
    }

    /**
     * Dedicated image-understanding model. This is intentionally separate from
     * the primary chat model because text-only models must not receive image
     * inputs from Telegram or other media channels.
     */
    public static var _imageModel: Option<String> = None
    public static mut prop imageModel: String {
        get() {
            return _imageModel.getOrThrow()
        }
        set(v) {
            _imageModel = Some(v)
        }
    }

    public static func imageModelOrEmpty(): String {
        match (_imageModel) {
            case Some(v) => v
            case None => ""
        }
    }

    public static func clearImageModelForTest(): Unit {
        _imageModel = None
    }

    /**
     * Fast model for auxiliary tasks in hybrid mode
     */
    public static var _fastModel: Option<String> = None

    public static mut prop fastModel: Option<String> {
        get() {
            if (let Some(m) <- _fastModel) {
                return m
            }
            if (let Some(m) <- CliSettingManager.setting.fastModel) {
                _fastModel = m
            }
            return _fastModel
        }

        set(v) {
            _fastModel = v
        }
    }

    /**
     * Fallback models to use when primary model fails
     */
    private static var _fallbackModels: Array<String> = []

    public static mut prop fallbackModels: Array<String> {
        get() {
            if (_fallbackModels.isEmpty()) {
                _fallbackModels = CliSettingManager.setting.fallbackModels
            }
            return _fallbackModels
        }

        set(v) {
            _fallbackModels = v
        }
    }

    private static var _imageFallbackModels: Array<String> = []

    public static mut prop imageFallbackModels: Array<String> {
        get() {
            if (_imageFallbackModels.isEmpty()) {
                _imageFallbackModels = CliSettingManager.setting.imageFallbackModels
            }
            return _imageFallbackModels
        }

        set(v) {
            _imageFallbackModels = v
        }
    }

    /**
     * The prompt when running magic-cli in non-interactive mode
     */
    public static var nonInteractive: Bool = false

    public static var nonInteractivePrompt: String = ""

    /**
     * The output format for non-interactive mode: plain | colorful
     */
    public static var nonInteractiveOutputFormat = "colorful"

    /**
     * The programming language setting for the CLI.
     * It will be set during the arguments parsing
     */
    public static var language: String = ""

    /**
     * Hidden internal built-in subagent selector used by managed background sessions.
     * Empty means use the normal top-level agent resolution.
     */
    public static var internalSubagent: String = ""

    /**
     * Hidden extra system prompt used only for internal built-in subagent runs.
     * This allows managed runtimes such as dreaming narrative generation to inject
     * Internal role guidance without affecting the normal top-level agent.
     */
    public static var internalSubagentSystemPrompt: String = ""

    /**
     * Active memory provider id for the current memory runtime.
     * It can be set via CLI flag or environment variable.
     */
    public static var memoryProvider: String = ""
    public static var memoryCitations: String = "auto"

    /**
     * External memory search backend command configuration.
     * This is intentionally search-only and is meant for qmd-like backends.
     */
    public static var externalMemoryCommand: String = ""
    public static var externalMemoryArgs: Array<String> = []
    public static var externalMemoryTimeoutMs: Int64 = 5000
    public static var externalMemoryBackendLabel: String = "external-command"
    public static var externalMemoryIndexPathHint: String = ""

    /**
     * Native QMD backend configuration surface.
     * Stage 1 wires the current config surface and provider identity without yet
     * implementing the full QMD manager/update/embed lifecycle.
     */
    public static var qmdCommand: String = "qmd"
    public static var qmdSearchMode: String = "search"
    public static var qmdSearchTool: String = ""
    public static var qmdIncludeDefaultMemory: Bool = true
    public static var qmdPathNames: Array<String> = []
    public static var qmdPaths: Array<String> = []
    public static var qmdPathPatterns: Array<String> = []
    public static var qmdSessionsEnabled: Bool = false
    public static var qmdSessionsExportDir: String = ""
    public static var qmdSessionsRetentionDays: Int64 = 0
    public static var qmdUpdateOnBoot: Bool = true
    public static var qmdUpdateWaitForBootSync: Bool = false
    public static var qmdUpdateIntervalMs: Int64 = 300000
    public static var qmdUpdateDebounceMs: Int64 = 15000
    public static var qmdUpdateEmbedIntervalMs: Int64 = 3600000
    public static var qmdUpdateCommandTimeoutMs: Int64 = 30000
    public static var qmdUpdateUpdateTimeoutMs: Int64 = 120000
    public static var qmdUpdateEmbedTimeoutMs: Int64 = 120000
    public static var qmdLimitsMaxResults: Int64 = 6
    public static var qmdLimitsMaxSnippetChars: Int64 = 700
    public static var qmdLimitsMaxInjectedChars: Int64 = 4000
    public static var qmdLimitsTimeoutMs: Int64 = 4000
    public static var qmdScopeDefault: String = "deny"
    public static var qmdScopeRuleActions: Array<String> = []
    public static var qmdScopeRuleChannels: Array<String> = []
    public static var qmdScopeRuleChatTypes: Array<String> = []
    public static var qmdScopeRuleKeyPrefixes: Array<String> = []
    public static var qmdScopeRuleRawKeyPrefixes: Array<String> = []
    public static var qmdMcporterEnabled: Bool = false
    public static var qmdMcporterServerName: String = "qmd"
    public static var qmdMcporterStartDaemon: Bool = true

    /**
     * Whether to run Gateway P0 demo mode.
     * In this mode, CLI will build and run the minimal gateway pipeline once.
     */
    public static var gatewayP0Demo: Bool = false

    /**
     * Whether to run Gateway P1 demo mode (real model + Feishu webhook payload mapping).
     */
    public static var gatewayP1Demo: Bool = false

    /**
     * Whether to run Feishu webhook gateway as a long-running service.
     */
    public static var gatewayFeishuWebhook: Bool = false

    /**
     * 为 true 时，交互式启动后在独立窗口/后台拉起网关（需 settings 中总开关与渠道已启用）。
     * 由命令行 `--run-args --start-gateway-window` 设置；默认 false，避免每次启动都多开网关。
     */
    public static var autoStartGatewayWindow: Bool = false

    public static prop userRules: String {
        get() {
            if (exists(agentsMarkdownPath)) {
                return String.fromUtf8(readToEnd(File(agentsMarkdownPath, OpenMode.Read)))
            }
            return ""
        }
    }

    /**
     * The directories to search for subagents
     */
    private static var _subagentDirs: Option<ArrayList<Path>> = None

    public static prop subagentDirs: ArrayList<Path> {
        get() {
            if (_subagentDirs.isNone()) {
                let agentDir = CliConfig.dotDir.join("agents")
                try {
                    // read all subdirectories
                    _subagentDirs = Directory.readFrom(agentDir) |> filterMap {
                        info: FileInfo => if (info.isDirectory()) {
                            info.path
                        } else {
                            None
                        }
                    } |> collectArrayList
                } catch (ex: Exception) {
                    LogUtils.error("Failed to load agent dirs from ${agentDir}, error is: ${ex.message}")
                    _subagentDirs = ArrayList<Path>()
                }
            }
            return _subagentDirs.getOrThrow()
        }
    }
    /**
     * The directories to search for commands
     */
    public static var commandDirs: ArrayList<Path> = ArrayList([CliConfig.dotDir.join("commands")])

    /**
     * The default input token limit for the model
     * The default value from CliSettingManager will be used.
     */
    public static var defaultModelInputLimit: Int64 = 128 * 1024

    /**
     * The default output token limit for the model
     * The default value from CliSettingManager will be used.
     */
    public static var defaultModelOutputLimit: Int64 = 32 * 1024

    /**
     * Code compression
     * When the number of characters of the code exceeds this threshold * LLM's content window * 4,
     * the code will be compressed.
     * The reason we multiple by 4 is because 1 token has about 4 characters on average.
     */
    public static var fileReadThreshold: Float64 = 0.05
    public static var fileBatchReadThreshold: Float64 = 0.1

    /**
     * Whether to enable LSP tools
     */
    public static var enableLSPTool: Bool = false

    public static func toString(): String {
        let strBuilder = StringBuilder()
        strBuilder.append("CliConfig Setting:\n")
        strBuilder.append("  version: ${CliConfig.version}\n")
        strBuilder.append("  language: ${CliConfig.language}\n")
        if (!CliConfig.internalSubagent.trimAscii().isEmpty()) {
            strBuilder.append("  internalSubagent: ${CliConfig.internalSubagent}\n")
        }
        strBuilder.append("  gatewayP0Demo: ${CliConfig.gatewayP0Demo}\n")
        strBuilder.append("  gatewayP1Demo: ${CliConfig.gatewayP1Demo}\n")
        strBuilder.append("  gatewayFeishuWebhook: ${CliConfig.gatewayFeishuWebhook}\n")
        strBuilder.append("  autoStartGatewayWindow: ${CliConfig.autoStartGatewayWindow}\n")
        strBuilder.append("  auto: ${CliConfig.auto}\n")
        strBuilder.append("  collectData: ${CliConfig.collectData}\n")
        strBuilder.append("  temperature: ${CliConfig.temperature}\n")
        strBuilder.append("  model: ${CliConfig.model}\n")
        strBuilder.append("  fastModel: ${CliConfig.fastModel}\n")
        strBuilder.append("  fallbackModels: ${CliConfig.fallbackModels}\n")
        // strBuilder.append("  nonInteractive: ${CliConfig.nonInteractive}\n")
        // strBuilder.append("  nonInteractivePrompt: ${CliConfig.nonInteractivePrompt}\n")
        strBuilder.append("  defaultModelInputLimit: ${CliConfig.defaultModelInputLimit}\n")
        strBuilder.append("  defaultModelOutputLimit: ${CliConfig.defaultModelOutputLimit}\n")
        strBuilder.append("  enableModelToolCall: ${Config.enableModelToolCall}\n")
        // strBuilder.append("  enableParallelToolCall: ${Config.enableParallelToolCall}\n")
        strBuilder.append("  fileReadThreshold: ${CliConfig.fileReadThreshold}\n")
        strBuilder.append("  fileBatchReadThreshold: ${CliConfig.fileBatchReadThreshold}\n")
        strBuilder.append("  subagentDirs: ${CliConfig.subagentDirs}\n")
        strBuilder.append("  commandDirs: ${CliConfig.commandDirs}\n")
        strBuilder.append("  enableLSPTool: ${CliConfig.enableLSPTool}\n")
        return strBuilder.toString()
    }

    /**
     * Clean up old log files based on retention policy
     * - Removes files older than logRetentionDays
     * - Keeps only the most recent logMaxFiles files
     */
    public static func cleanupLogs(): Unit {
        try {
            if (!exists(logsDir)) {
                return
            }

            let retentionDays = CliSettingManager.setting.logRetentionDays
            let maxFiles = CliSettingManager.setting.logMaxFiles

            var logFiles = ArrayList<Path>()
            for (entry in Directory.readFrom(logsDir)) {
                if (entry.isRegular() && entry.name.endsWith(".log")) {
                    logFiles.add(entry.path)
                }
            }

            if (logFiles.isEmpty()) {
                return
            }

            // Sort by file name (oldest first)
            sort(logFiles, by: { a, b => a.fileName.compare(b.fileName) })

            // Step 1: Delete files older than retention days
            let now = DateTime.now()
            var filesToKeep = ArrayList<Path>()

            for (filePath in logFiles) {
                try {
                    // Extract date from filename
                    let fileName = filePath.fileName
                    let parts = fileName.split("-")
                    if (parts.size >= 2) {
                        let datePart = parts[0].replace("_", "-")
                        let fileDate = DateTime.parse(datePart, "yyyy-MM-dd")
                        let age = now - fileDate
                        let ageDays = age.toDays()

                        if (ageDays > retentionDays) {
                            remove(filePath)
                            LogUtils.info("Deleted old log file: ${filePath}")
                            continue
                        }
                    }
                    filesToKeep.add(filePath)
                } catch (e: Exception) {
                    LogUtils.error("Failed to parse date for ${filePath}: ${e}")
                    filesToKeep.add(filePath) // Keep files we can't parse
                }
            }

            // Step 2: If still too many files, delete oldest ones
            if (filesToKeep.size > maxFiles) {
                let toDelete = filesToKeep.size - maxFiles
                for (i in 0..toDelete) {
                    let filePath = filesToKeep[i]
                    try {
                        remove(filePath)
                        LogUtils.info("Deleted excess log file: ${filePath}")
                    } catch (e: Exception) {
                        LogUtils.error("Failed to delete log file ${filePath}: ${e}")
                    }
                }
            }
        } catch (e: Exception) {
            LogUtils.error("Failed to cleanup logs: ${e}")
        }
    }
}
