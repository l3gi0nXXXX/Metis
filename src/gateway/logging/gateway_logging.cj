package metis.gateway.logging

import magic.config.Config

import metis.core.config.{CliConfig, CliSettingManager, GatewayLoggingUserSettings}

import std.collection.ArrayList
import std.env.getVariable
import std.fs.{Directory, File, Path, exists}
import std.regex.{Regex, RegexFlag}
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonBool, JsonFloat, JsonInt, JsonObject, JsonString, JsonValue}

public class MetisLogLevel {
    public static const trace: String = "trace"
    public static const debug: String = "debug"
    public static const info: String = "info"
    public static const warn: String = "warn"
    public static const error: String = "error"
    public static const fatal: String = "fatal"
    public static const silent: String = "silent"
}

public class MetisLogEvent {
    public static const gatewayStarting: String = "gateway.starting"
    public static const gatewayReady: String = "gateway.ready"
    public static const gatewayShutdown: String = "gateway.shutdown"
    public static const channelRegistered: String = "channel.registered"
    public static const channelStarting: String = "channel.starting"
    public static const channelStarted: String = "channel.started"
    public static const channelFailed: String = "channel.failed"
    public static const channelStopped: String = "channel.stopped"
    public static const channelTiming: String = "channel.timing"
    public static const channelStartupSummary: String = "channel.startup_summary"
    public static const channelPull: String = "channel.pull"
    public static const channelSend: String = "channel.send"
    public static const messageInbound: String = "message.inbound"
    public static const messageInboundPreview: String = "message.inbound.preview"
    public static const messageRouted: String = "message.routed"
    public static const messageReplyGenerated: String = "message.reply.generated"
    public static const messageOutbound: String = "message.outbound"
    public static const messageSent: String = "message.sent"
    public static const messageSendFailed: String = "message.send_failed"
    public static const modelRequest: String = "model.request"
    public static const modelResponse: String = "model.response"
    public static const modelFailed: String = "model.failed"
    public static const rpcSlow: String = "rpc.slow"
    public static const rpcFailed: String = "rpc.failed"
    public static const loggingRaw: String = "logging.raw"

    public static func all(): Array<String> {
        [
            gatewayStarting, gatewayReady, gatewayShutdown, channelRegistered, channelStarting,
            channelStarted, channelFailed, channelStopped, channelTiming, channelStartupSummary,
            channelPull, channelSend, messageInbound, messageInboundPreview, messageRouted,
            messageReplyGenerated, messageOutbound, messageSent, messageSendFailed,
            modelRequest, modelResponse, modelFailed, rpcSlow, rpcFailed, loggingRaw
        ]
    }
}

public class GatewayResolvedLoggingSettings {
    public let level: String
    public let file: String
    public let consoleLevel: String
    public let consoleStyle: String
    public let maxFileBytes: Int64
    public let redactSensitive: Bool
    public let redactPatterns: Array<String>

    public init(
        level: String,
        file: String,
        consoleLevel: String,
        consoleStyle: String,
        maxFileBytes: Int64,
        redactSensitive: Bool,
        redactPatterns: Array<String>
    ) {
        this.level = level
        this.file = file
        this.consoleLevel = consoleLevel
        this.consoleStyle = consoleStyle
        this.maxFileBytes = maxFileBytes
        this.redactSensitive = redactSensitive
        this.redactPatterns = redactPatterns
    }
}

private let DEFAULT_MAX_LOG_FILE_BYTES: Int64 = 500 * 1024 * 1024
private let LOG_MESSAGE_LIMIT: Int64 = 500
private let LOG_META_STRING_LIMIT: Int64 = 1000
private let LOG_TRUNCATED_MARKER: String = "...[truncated]"

private var cachedGatewayLoggingSettings: Option<GatewayResolvedLoggingSettings> = None
private var gatewayLoggingConsoleCaptureForTest: Option<ArrayList<String>> = None

private func gatewayLogLevelRank(level: String): Int64 {
    match (level.trimAscii().toAsciiLower()) {
        case "fatal" => 0
        case "error" => 1
        case "warn" => 2
        case "info" => 3
        case "debug" => 4
        case "trace" => 5
        case _ => -1
    }
}

private func gatewayLoggingNormalizeLevel(raw: String, fallback: String): String {
    let level = raw.trimAscii().toAsciiLower()
    if (level == "silent") {
        return "silent"
    }
    if (gatewayLogLevelRank(level) >= 0) {
        return level
    }
    fallback
}

private func gatewayLoggingNormalizeStyle(raw: String, fallback: String): String {
    let style = raw.trimAscii().toAsciiLower()
    if (style == "pretty" || style == "compact" || style == "json") {
        return style
    }
    fallback
}

private func gatewayLoggingEnv(name: String): String {
    match (getVariable(name)) {
        case Some(value) => value.trimAscii()
        case None => ""
    }
}

private func gatewayLoggingDefaultFile(): String {
    CliConfig.logsDir.join("metis-gateway-${DateTime.now().format("yyyy-MM-dd")}.log").toString()
}

private func gatewayLoggingReadUserSettings(): GatewayLoggingUserSettings {
    try {
        CliSettingManager.readGatewaySettings().logging
    } catch (_: Exception) {
        GatewayLoggingUserSettings()
    }
}

public func gatewayLoggingResolveSettings(): GatewayResolvedLoggingSettings {
    if (let Some(settings) <- cachedGatewayLoggingSettings) {
        return settings
    }
    let user = gatewayLoggingReadUserSettings()
    let envLevel = gatewayLoggingEnv("METIS_LOG_LEVEL")
    let envFile = gatewayLoggingEnv("METIS_LOG_FILE")
    let envConsoleLevel = gatewayLoggingEnv("METIS_CONSOLE_LEVEL")
    let envConsoleStyle = gatewayLoggingEnv("METIS_CONSOLE_STYLE")
    let level = gatewayLoggingNormalizeLevel(
        if (!envLevel.isEmpty()) { envLevel } else { user.level },
        "info"
    )
    let file = if (!envFile.isEmpty()) {
        envFile
    } else if (!user.file.trimAscii().isEmpty()) {
        user.file.trimAscii()
    } else {
        gatewayLoggingDefaultFile()
    }
    let consoleLevel = gatewayLoggingNormalizeLevel(
        if (!envConsoleLevel.isEmpty()) { envConsoleLevel } else { user.consoleLevel },
        "info"
    )
    let consoleStyle = gatewayLoggingNormalizeStyle(
        if (!envConsoleStyle.isEmpty()) { envConsoleStyle } else { user.consoleStyle },
        "compact"
    )
    let maxBytes = if (user.maxFileBytes > 0) { user.maxFileBytes } else { DEFAULT_MAX_LOG_FILE_BYTES }
    let settings = GatewayResolvedLoggingSettings(
        level,
        file,
        consoleLevel,
        consoleStyle,
        maxBytes,
        user.redactSensitive,
        user.redactPatterns
    )
    cachedGatewayLoggingSettings = Some(settings)
    Config.logFile = settings.file
    return settings
}

public func gatewayLoggingCurrentLogFile(): String {
    gatewayLoggingResolveSettings().file
}

public func gatewayLoggingResetForTest(): Unit {
    cachedGatewayLoggingSettings = None<GatewayResolvedLoggingSettings>
    gatewayLoggingConsoleCaptureForTest = None<ArrayList<String>>
}

public func gatewayLoggingCaptureConsoleForTest(): Unit {
    gatewayLoggingConsoleCaptureForTest = Some(ArrayList<String>())
}

public func gatewayLoggingCapturedConsoleForTest(): Array<String> {
    match (gatewayLoggingConsoleCaptureForTest) {
        case Some(lines) => lines.toArray()
        case None => []
    }
}

private func gatewayLogRegexReplace(text: String, pattern: String, replacement: String): String {
    try {
        Regex(pattern, [RegexFlag.IgnoreCase]).replaceAll(text, replacement)
    } catch (_: Exception) {
        text
    }
}

public func gatewayLogTruncateText(text: String, limit!: Int64 = LOG_META_STRING_LIMIT): String {
    if (limit <= 0 || Int64(text.size) <= limit) {
        return text
    }
    let keep = limit - Int64(LOG_TRUNCATED_MARKER.size)
    if (keep <= 0) {
        return LOG_TRUNCATED_MARKER
    }
    text[0..keep] + LOG_TRUNCATED_MARKER
}

public func gatewayLogRedactText(text: String): String {
    var out = text
    let settings = gatewayLoggingResolveSettings()
    if (!settings.redactSensitive) {
        return out
    }
    out = gatewayLogRegexReplace(out, "Authorization\\s*[:=]\\s*Bearer\\s+[^\\s,;\\}\\]]+", "Authorization: Bearer [redacted]")
    out = gatewayLogRegexReplace(out, "Authorization\\s*[:=]\\s*[^\\s,;\\}\\]]+", "Authorization: [redacted]")
    out = gatewayLogRegexReplace(out, "Bearer\\s+[^\\s,;\\}\\]]+", "Bearer [redacted]")
    out = gatewayLogRegexReplace(out, "[0-9]{5,}:[A-Za-z0-9_-]{6,}", "[redacted]")
    out = gatewayLogRegexReplace(out, "app[_-]?secret[_a-zA-Z0-9-]*", "[redacted]")
    out = gatewayLogRegexReplace(out, "api[_-]?key\\s*[:=]\\s*[^\\s,;\\}\\]]+", "api_key=[redacted]")
    out = gatewayLogRegexReplace(out, "(https?://[^\\s:/@]+:)[^\\s/@]+(@)", "$1[redacted]$2")
    for (pattern in settings.redactPatterns) {
        let p = pattern.trimAscii()
        if (!p.isEmpty()) {
            out = gatewayLogRegexReplace(out, p, "[redacted]")
        }
    }
    out
}

private func gatewayLogSanitizeString(text: String, limit: Int64): String {
    gatewayLogTruncateText(gatewayLogRedactText(text), limit: limit)
}

private func gatewayLogSanitizeJsonValue(key: String, value: JsonValue): JsonValue {
    match (value) {
        case s: JsonString =>
            JsonString(gatewayLogSanitizeString(s.getValue(), LOG_META_STRING_LIMIT))
        case o: JsonObject =>
            let out = JsonObject()
            for (field in o.getFields().keys()) {
                match (o.get(field)) {
                    case Some(child) => out.put(field, gatewayLogSanitizeJsonValue(field, child))
                    case None => ()
                }
            }
            out
        case a: JsonArray =>
            let items = ArrayList<JsonValue>()
            for (item in a.getItems()) {
                items.add(gatewayLogSanitizeJsonValue(key, item))
            }
            JsonArray(items)
        case b: JsonBool => b
        case i: JsonInt => i
        case f: JsonFloat => f
        case _ => JsonString(gatewayLogSanitizeString(value.toJsonString(), LOG_META_STRING_LIMIT))
    }
}

private func gatewayLogSanitizeMeta(meta: JsonObject): JsonObject {
    let out = JsonObject()
    for (key in meta.getFields().keys()) {
        match (meta.get(key)) {
            case Some(value) => out.put(key, gatewayLogSanitizeJsonValue(key, value))
            case None => ()
        }
    }
    out
}

private func gatewayLoggingLevelEnabled(level: String, configured: String): Bool {
    if (configured == "silent") {
        return false
    }
    let current = gatewayLogLevelRank(level)
    let threshold = gatewayLogLevelRank(configured)
    current >= 0 && threshold >= 0 && current <= threshold
}

public func gatewayLogEventIsKnown(event: String): Bool {
    let normalized = event.trimAscii()
    for (known in MetisLogEvent.all()) {
        if (known == normalized) {
            return true
        }
    }
    false
}

public class MetisSubsystemLogger {
    public let subsystem: String

    public init(subsystem: String) {
        this.subsystem = gatewayNormalizeSubsystem(subsystem)
    }

    public func isEnabled(level: String, target!: String = "any"): Bool {
        let settings = gatewayLoggingResolveSettings()
        let fileEnabled = gatewayLoggingLevelEnabled(level, settings.level)
        let consoleEnabled = gatewayLoggingLevelEnabled(level, settings.consoleLevel)
        match (target.trimAscii().toAsciiLower()) {
            case "file" => fileEnabled
            case "console" => consoleEnabled
            case _ => fileEnabled || consoleEnabled
        }
    }

    public func trace(event: String, message: String, meta!: JsonObject = JsonObject(), consoleMessage!: String = ""): Unit {
        this.log("trace", event, message, meta: meta, consoleMessage: consoleMessage)
    }

    public func debug(event: String, message: String, meta!: JsonObject = JsonObject(), consoleMessage!: String = ""): Unit {
        this.log("debug", event, message, meta: meta, consoleMessage: consoleMessage)
    }

    public func info(event: String, message: String, meta!: JsonObject = JsonObject(), consoleMessage!: String = ""): Unit {
        this.log("info", event, message, meta: meta, consoleMessage: consoleMessage)
    }

    public func warn(event: String, message: String, meta!: JsonObject = JsonObject(), consoleMessage!: String = ""): Unit {
        this.log("warn", event, message, meta: meta, consoleMessage: consoleMessage)
    }

    public func error(event: String, message: String, meta!: JsonObject = JsonObject(), consoleMessage!: String = ""): Unit {
        this.log("error", event, message, meta: meta, consoleMessage: consoleMessage)
    }

    public func fatal(event: String, message: String, meta!: JsonObject = JsonObject(), consoleMessage!: String = ""): Unit {
        this.log("fatal", event, message, meta: meta, consoleMessage: consoleMessage)
    }

    public func raw(message: String, meta!: JsonObject = JsonObject()): Unit {
        this.log("info", MetisLogEvent.loggingRaw, message, meta: meta, consoleMessage: message, raw: true)
    }

    public func child(segment: String): MetisSubsystemLogger {
        MetisSubsystemLogger("${this.subsystem}/${gatewayNormalizeSubsystemSegment(segment)}")
    }

    private func log(
        level: String,
        event: String,
        message: String,
        meta!: JsonObject = JsonObject(),
        consoleMessage!: String = "",
        raw!: Bool = false
    ): Unit {
        let settings = gatewayLoggingResolveSettings()
        let safeMessage = gatewayLogSanitizeString(message, LOG_MESSAGE_LIMIT)
        let safeConsoleMessage = if (consoleMessage.trimAscii().isEmpty()) {
            safeMessage
        } else {
            gatewayLogSanitizeString(consoleMessage, LOG_MESSAGE_LIMIT)
        }
        let safeMeta = gatewayLogSanitizeMeta(meta)
        if (gatewayLoggingLevelEnabled(level, settings.level)) {
            this.writeFile(settings, level, event, safeMessage, safeMeta)
        }
        if (gatewayLoggingLevelEnabled(level, settings.consoleLevel)) {
            this.writeConsole(settings, level, event, safeConsoleMessage, safeMeta, raw: raw)
        }
    }

    private func writeFile(settings: GatewayResolvedLoggingSettings, level: String, event: String, message: String, meta: JsonObject): Unit {
        try {
            let path = Path(settings.file)
            if (!exists(path.parent)) {
                Directory.create(path.parent, recursive: true)
            }
            let row = JsonObject()
            row.put("time", JsonString(DateTime.now().format("yyyy-MM-dd'T'HH:mm:ss.SSS")))
            row.put("level", JsonString(level))
            row.put("subsystem", JsonString(this.subsystem))
            row.put("event", JsonString(if (gatewayLogEventIsKnown(event)) { event } else { MetisLogEvent.loggingRaw }))
            row.put("message", JsonString(message))
            for (key in meta.getFields().keys()) {
                match (meta.get(key)) {
                    case Some(value) => row.put(key, value)
                    case None => ()
                }
            }
            let line = row.toJsonString() + "\n"
            let nextSize = if (exists(path)) { Int64(File.readFrom(path).size) + Int64(line.size) } else { Int64(line.size) }
            if (settings.maxFileBytes > 0 && nextSize > settings.maxFileBytes) {
                return
            }
            File.appendTo(path, line.toArray())
        } catch (_: Exception) {
            ()
        }
    }

    private func writeConsole(
        settings: GatewayResolvedLoggingSettings,
        level: String,
        event: String,
        message: String,
        meta: JsonObject,
        raw!: Bool = false
    ): Unit {
        let line = if (raw) {
            message
        } else if (settings.consoleStyle == "json") {
            let row = JsonObject()
            row.put("time", JsonString(DateTime.now().format("yyyy-MM-dd'T'HH:mm:ss.SSS")))
            row.put("level", JsonString(level))
            row.put("subsystem", JsonString(this.subsystem))
            row.put("event", JsonString(event))
            row.put("message", JsonString(message))
            row.toJsonString()
        } else {
            "[${this.subsystem}] ${level} ${event} ${message}${gatewayConsoleMetaSuffix(meta)}"
        }
        match (gatewayLoggingConsoleCaptureForTest) {
            case Some(lines) => lines.add(line)
            case None =>
                if (level == "warn" || level == "error" || level == "fatal") {
                    eprintln(line)
                } else {
                    println(line)
                }
        }
    }
}

private func gatewayNormalizeSubsystem(raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return "gateway"
    }
    let parts = ArrayList<String>()
    for (part in trimmed.split("/")) {
        let segment = gatewayNormalizeSubsystemSegment(part)
        if (!segment.isEmpty()) {
            parts.add(segment)
        }
    }
    if (parts.isEmpty()) {
        "gateway"
    } else {
        String.join(parts.toArray(), delimiter: "/")
    }
}

private func gatewayNormalizeSubsystemSegment(raw: String): String {
    raw.trimAscii().replace(" ", "-").replace("\\", "/").replace("..", "").replace(":", "-")
}

private func gatewayConsoleMetaSuffix(meta: JsonObject): String {
    if (meta.size() <= 0) {
        return ""
    }
    let parts = ArrayList<String>()
    for (key in meta.getFields().keys()) {
        match (meta.get(key)) {
            case Some(value) => parts.add("${key}=${gatewayLogTruncateText(value.toJsonString(), limit: 160)}")
            case None => ()
        }
    }
    if (parts.isEmpty()) {
        ""
    } else {
        " " + String.join(parts.toArray(), delimiter: " ")
    }
}

public func metisGetLogger(): MetisSubsystemLogger {
    MetisSubsystemLogger("gateway")
}

public func metisCreateSubsystemLogger(subsystem: String): MetisSubsystemLogger {
    MetisSubsystemLogger(subsystem)
}
