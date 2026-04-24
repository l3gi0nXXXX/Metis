package metis

import magic.config.Config
import magic.log.LogUtils
import magic.utils.readFile
import magic.model.ModelManager

import metis.core.config.{CliConfig, CliSettingManager, MetisConfigManager, MetisPaths}
import metis.core.memory.MemoryRuntimeRegistry
import metis.core.skills.SkillsPrompt
import metis.io.PrintUtils
import metis.program.printRootHelp
import metis.core.model.ModelTokenLimits

import std.collection.{ArrayList, map, collectArray}
import std.argopt.{parseArguments, ArgumentSpec, ArgumentMode, ArgumentParseException}
import std.time.*
import std.fs.*
import std.convert.Parsable

enum ParseArgsResult {
    | Continue
    | Exit
    | Sandbox
}

func printHelp(): Unit {
    printRootHelp()
}

private func parseDurationOrMs(raw: String): Option<Int64> {
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

/**
 * Parse the command line arguments
 */
func parseArgsAndSetConfig(args: Array<String>): ParseArgsResult {
    let argSpecs = [
        Long("auto", NoValue),
        Long("model", RequiredValue),
        Long("fast-model", RequiredValue),
        Long("fallback-models", RequiredValue),
        Long("collect-data", NoValue),
        Long("sandbox", NoValue),
        Full("language", r"l", RequiredValue),
        Long("subagent-dir", RequiredValue),
        Long("command-dir",  RequiredValue),
        Full("help", r"h", NoValue),
        Full("version", r"v", NoValue),
        Full("prompt", r"p", RequiredValue),
        Long("prompt-file", RequiredValue),
        Long("output-format", RequiredValue),
        Full("temperature", r"t", RequiredValue),
        Long("log-level", RequiredValue),
        Long("default-model-input-limit", RequiredValue),
        Long("default-model-output-limit", RequiredValue),
        Long("disable-model-tool-call", NoValue),
        Long("enable-lsp-tool", NoValue),
        Long("memory-provider", RequiredValue),
        Long("gateway-p0-demo", NoValue),
        Long("gateway-p1-demo", NoValue),
        Long("gateway-feishu-webhook", NoValue),
        Long("start-gateway-window", NoValue),
        Long("internal-subagent", RequiredValue),
        Long("internal-system-prompt-file", RequiredValue)
    ]
    let result = try {
        parseArguments(args, argSpecs)
    } catch (ex: ArgumentParseException) {
        PrintUtils.printLine(ex.message)
        return ParseArgsResult.Exit
    }
    if (result.options.contains("help") || result.options.contains("h")) {
        printHelp()
        return ParseArgsResult.Exit
    }
    if (result.options.contains("version") || result.options.contains("v")) {
        PrintUtils.printLine(CliConfig.version)
        return ParseArgsResult.Exit
    }

    // Log level must be set first
    if (let Some(level) <- result.options.get("log-level")) {
        Config.logLevel = level
    } else {
        Config.logLevel = "INFO"
    }
    // Log file must be set together with the log level
    Config.logFile = CliConfig.logFile.toString()

    // Clean up old log files based on retention policy
    CliConfig.cleanupLogs()

    MetisConfigManager.initializeIfMissing()
    MetisConfigManager.migrateLegacyIfNeeded()

    // Now, we can start the sandbox because it will inherits environment variables
    if (result.options.contains("sandbox")) {
        return ParseArgsResult.Sandbox
    }

    // Set Magic settings
    Config.modelRequestDir = CliConfig.dotDir.join("model-requests").toString()
    Config.enableModelToolCall = !result.options.contains("disable-model-tool-call")
    Config.enableParallelToolCall = false
    Config.httpReadWriteTimeout = 600000 // ms

    if (result.options.contains("subagent-dir")) {
        let option = result.options.get("subagent-dir").getOrThrow()
        for (dir in option.trimAscii().split(",")) {
            if (exists(dir)) {
                CliConfig.subagentDirs.add(Path(dir))
            }
        }
    }

    if (result.options.contains("command-dir")) {
        let option = result.options.get("command-dir").getOrThrow()
        for (dir in option.trimAscii().split(",")) {
            if (exists(dir)) {
                CliConfig.commandDirs.add(Path(dir))
            }
        }
    }

    // Set Magic-Cli settings
    if (result.options.contains("auto")) {
        CliConfig.auto = true
    }

    if (result.options.contains("collect-data")) {
        CliConfig.collectData = true
    }

    // Initialize the main model
    if (let Some(model) <- result.options.get("model")) {
        CliConfig.model = MetisConfigManager.setPrimaryModelRef(model)
    } else {
        CliConfig.model = CliSettingManager.setting.model
    }

    if (let Some(model) <- result.options.get("fast-model")) {
        CliConfig.fastModel = Some(MetisConfigManager.setFastModelRef(model))
    }

    // Set fallback models if provided
    if (let Some(modelsStr) <- result.options.get("fallback-models")) {
        let models = modelsStr.split(",") |>
            map { model => model.trimAscii() } |>
            collectArray
        CliConfig.fallbackModels = MetisConfigManager.setFallbackModelRefs(models)
    }

    // Legacy persisted config should override settings defaults, but
    // explicit CLI flags must still win over persisted config.
    MetisConfigManager.applyPersistedFieldsToCliConfig()
    if (let Some(model) <- result.options.get("model")) {
        CliConfig.model = model
    }

    if (let Some(inputLimit) <- result.options.get("default-model-input-limit")) {
        try {
            let inputLimit = Int64.parse(inputLimit)
            CliConfig.defaultModelInputLimit = MetisConfigManager.setDefaultModelInputLimit(inputLimit)
        } catch (ex: IllegalArgumentException) {
            PrintUtils.printLine("Failed to parse default-model-input-limit: ${ex.message}")
            return ParseArgsResult.Exit
        }
    } else {
        CliConfig.defaultModelInputLimit = CliSettingManager.setting.defaultModelInputLimit
    }

    if (let Some(outputLimit) <- result.options.get("default-model-output-limit")) {
        try {
            let outputLimit = Int64.parse(outputLimit)
            CliConfig.defaultModelOutputLimit = MetisConfigManager.setDefaultModelOutputLimit(outputLimit)
        } catch (ex: IllegalArgumentException) {
            PrintUtils.printLine("Failed to parse default-model-output-limit: ${ex.message}")
            return ParseArgsResult.Exit
        }
    } else {
        CliConfig.defaultModelOutputLimit = CliSettingManager.setting.defaultModelOutputLimit
    }

    if (let Some(temperature) <- result.options.get("temperature")) {
        try {
            let temperature = Float64.parse(temperature)
            CliConfig.temperature = MetisConfigManager.setTemperature(temperature)
        } catch (ex: IllegalArgumentException) {
            PrintUtils.printLine("Failed to parse temperature: ${ex.message}")
            return ParseArgsResult.Exit
        }
    } else {
        CliConfig.temperature = CliSettingManager.setting.temperature
    }

    if (result.options.contains("prompt-file")) {
        let promptFile = result.options.get("prompt-file").getOrThrow()
        if (exists(promptFile)) {
            let content = readFile(Path(promptFile))
            CliConfig.nonInteractive = true
            CliConfig.auto = true
            CliConfig.nonInteractivePrompt = content
        } else {
            LogUtils.error("Failed to read prompt file: ${promptFile}")
            return ParseArgsResult.Exit
        }
    }

    // It can override the prompt file
    if (result.options.contains("prompt") || result.options.contains("p")) {
        let prompt = result.options.get("prompt").getOrDefault { result.options.get("p").getOrThrow() }
        CliConfig.nonInteractive = true
        CliConfig.auto = true
        CliConfig.nonInteractivePrompt = prompt
    }

    if (let Some(format) <- result.options.get("output-format")) {
        if (format == "colorful") {
            CliConfig.nonInteractiveOutputFormat = "colorful"
        } else {
            CliConfig.nonInteractiveOutputFormat = "plain"
        }
    }

    if (let Some(language) <- result.options.get("language")) {
        CliConfig.language = MetisConfigManager.setLanguage(language)
    } else if (let Some(language) <- result.options.get("l")) {
        CliConfig.language = MetisConfigManager.setLanguage(language)
    } else {
        CliConfig.language = CliSettingManager.setting.language
    }

    if (result.options.contains("collect-data")) {
        CliConfig.collectData = MetisConfigManager.setCollectData(true)
    } else {
        CliConfig.collectData = CliSettingManager.setting.collectData
    }

    if (result.options.contains("enable-lsp-tool")) {
        CliConfig.enableLSPTool = true
    }

    if (let Some(provider) <- result.options.get("memory-provider")) {
        CliConfig.memoryProvider = MetisConfigManager.setMemoryBackend(provider)
    } else if (!CliSettingManager.setting.memory.backend.trimAscii().isEmpty()) {
        CliConfig.memoryProvider = CliSettingManager.setting.memory.backend.trimAscii()
    } else if (!CliSettingManager.setting.memoryProvider.trimAscii().isEmpty()) {
        CliConfig.memoryProvider = CliSettingManager.setting.memoryProvider.trimAscii()
    } else {
        CliConfig.memoryProvider = "local"
    }
    if (CliConfig.memoryProvider.isEmpty()) {
        CliConfig.memoryProvider = "local"
    }
    if (!MemoryRuntimeRegistry.activateBackend(CliConfig.memoryProvider)) {
        let available = String.join(MemoryRuntimeRegistry.registeredBackendSelectionKeys(), delimiter: ", ")
        PrintUtils.printLine("Unknown memory backend: ${CliConfig.memoryProvider}. Available backends: ${available}")
        return ParseArgsResult.Exit
    }

    if (result.options.contains("gateway-p0-demo")) {
        CliConfig.gatewayP0Demo = true
    }
    if (result.options.contains("gateway-p1-demo")) {
        CliConfig.gatewayP1Demo = true
    }
    if (result.options.contains("gateway-feishu-webhook")) {
        CliConfig.gatewayFeishuWebhook = true
    }
    if (result.options.contains("start-gateway-window")) {
        CliConfig.autoStartGatewayWindow = true
    }

    if (let Some(name) <- result.options.get("internal-subagent")) {
        CliConfig.internalSubagent = name.trimAscii()
    }
    if (let Some(path) <- result.options.get("internal-system-prompt-file")) {
        if (exists(path)) {
            CliConfig.internalSubagentSystemPrompt = readFile(Path(path))
        } else {
            LogUtils.error("Failed to read internal system prompt file: ${path}")
            return ParseArgsResult.Exit
        }
    }

    SkillsPrompt.invalidate()
    return ParseArgsResult.Continue
}
