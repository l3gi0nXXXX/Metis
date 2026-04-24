package metis.core.memory

import magic.prelude.*

import metis.core.config.CliConfig

import std.fs.{Path, Directory, File, FileInfo, OpenMode, exists}
import std.time.DateTime
import stdx.encoding.json.{JsonObject, JsonString, JsonValue}

private func dmReadTextFileOrEmpty(path: Path): String {
    try {
        String.fromUtf8(File.readFrom(path))
    } catch (_e: Exception) {
        ""
    }
}

private func dmWithTrailingNewline(content: String): String {
    if (content.endsWith("\n")) {
        return content
    }
    content + "\n"
}

private func dmReplaceManagedBlock(
    original: String,
    heading: String,
    startMarker: String,
    endMarker: String,
    body: String
): String {
    let managedBlock = "${heading}\n${startMarker}\n${body}\n${endMarker}"
    let startIdx = original.indexOf(startMarker)
    let endIdx = original.indexOf(endMarker)
    if (let Some(start) <- startIdx) {
        if (let Some(end) <- endIdx) {
            let lineStart = match (original[..start].lastIndexOf(heading)) {
                case Some(idx) => idx
                case None => start
            }
            let suffixStart = end + endMarker.size
            let prefix = original[..lineStart].trimAscii()
            let suffix = if (suffixStart < original.size) { original[suffixStart..].trimAscii() } else { "" }
            if (prefix.isEmpty() && suffix.isEmpty()) {
                return managedBlock + "\n"
            }
            if (suffix.isEmpty()) {
                return prefix + "\n\n" + managedBlock + "\n"
            }
            if (prefix.isEmpty()) {
                return managedBlock + "\n\n" + suffix + "\n"
            }
            return prefix + "\n\n" + managedBlock + "\n\n" + suffix + "\n"
        }
    }
    let trimmed = original.trimEnd()
    if (trimmed.isEmpty()) {
        return managedBlock + "\n"
    }
    trimmed + "\n\n" + managedBlock + "\n"
}

private func primaryDreamsPath(): Path {
    CliConfig.cwd.join("DREAMS.md")
}

private func legacyDreamsPath(): Path {
    CliConfig.cwd.join("dreams.md")
}

public class DreamingMarkdownStorageConfig {
    public let mode: String
    public let separateReports: Bool

    public init(mode: String, separateReports!: Bool = false) {
        this.mode = mode.trimAscii().toAsciiLower()
        this.separateReports = separateReports
    }
}

public class DreamingMarkdownWriteResult {
    public let inlinePath: String
    public let reportPath: String

    public init(inlinePath: String, reportPath: String) {
        this.inlinePath = inlinePath
        this.reportPath = reportPath
    }
}

public class DreamingMarkdownRuntime {
    public static func configPath(): Path {
        let dir = CliConfig.dotDir.join("memory")
        if (!exists(dir)) {
            Directory.create(dir, recursive: true)
        }
        dir.join("dreaming-markdown.json")
    }

    public static func resolveDreamsPath(): Path {
        let primary = primaryDreamsPath()
        let legacy = legacyDreamsPath()
        if (exists(primary)) {
            return primary
        }
        if (exists(legacy)) {
            return legacy
        }
        primary
    }

    public static func readStorageConfig(): DreamingMarkdownStorageConfig {
        let path = configPath()
        if (!exists(path)) {
            return DreamingMarkdownStorageConfig("both", separateReports: true)
        }
        try {
            match (JsonValue.fromStr(dmReadTextFileOrEmpty(path))) {
                case obj: JsonObject =>
                    let mode = match (obj.get("mode")) {
                        case Some(s: JsonString) => normalizeMode(s.getValue())
                        case _ => "both"
                    }
                    let separateReports = match (obj.get("separateReports")) {
                        case Some(v) =>
                            try {
                                v.asBool().getValue()
                            } catch (_e: Exception) {
                                mode == "separate" || mode == "both"
                            }
                        case _ => mode == "separate" || mode == "both"
                    }
                    DreamingMarkdownStorageConfig(mode, separateReports: separateReports)
                case _ => DreamingMarkdownStorageConfig("both", separateReports: true)
            }
        } catch (_e: Exception) {
            DreamingMarkdownStorageConfig("both", separateReports: true)
        }
    }

    public static func writeDefaultConfig(): String {
        let path = configPath()
        let root = JsonObject()
        root.put("mode", JsonString("both"))
        root.put("separateReports", true.toJsonValue())
        File.writeTo(path, dmWithTrailingNewline(root.toJsonString()).toArray())
        path.toString()
    }

    public static func buildStatusJson(): String {
        let config = readStorageConfig()
        let root = JsonObject()
        root.put("status", JsonString("ok"))
        root.put("action", JsonString("memory_dreaming_markdown_status"))
        root.put("configPath", JsonString(configPath().toString()))
        root.put("configPresent", exists(configPath()).toJsonValue())
        root.put("dreamsPath", JsonString(resolveDreamsPath().toString()))
        root.put("mode", JsonString(config.mode))
        root.put("separateReports", config.separateReports.toJsonValue())
        root.toJsonString()
    }

    public static func fixArtifacts(): Array<String> {
        let fixes = ArrayList<String>()
        let path = configPath()
        if (!exists(path)) {
            fixes.add("created dreaming markdown config: ${writeDefaultConfig()}")
        } else {
            let _ = readStorageConfig()
            let root = JsonObject()
            let config = readStorageConfig()
            root.put("mode", JsonString(config.mode))
            root.put("separateReports", config.separateReports.toJsonValue())
            File.writeTo(path, dmWithTrailingNewline(root.toJsonString()).toArray())
            fixes.add("normalized dreaming markdown config: ${path}")
        }
        fixes.toArray()
    }

    public static func writeDailyDreamingPhaseBlock(
        phase: String,
        bodyLines: Array<String>,
        now!: DateTime = DateTime.now()
    ): DreamingMarkdownWriteResult {
        let config = readStorageConfig()
        let normalizedPhase = phase.trimAscii().toAsciiLower()
        let body = if (bodyLines.isEmpty()) { "- No notable updates." } else { String.join(bodyLines, delimiter: "\n") }
        var inlinePath = ""
        var reportPath = ""

        if (shouldWriteInline(config)) {
            let dreamsPath = resolveDreamsPath()
            let original = if (exists(dreamsPath)) { dmReadTextFileOrEmpty(dreamsPath) } else { "" }
            let updated = dmReplaceManagedBlock(
                original,
                dmDreamingPhaseHeading(normalizedPhase),
                dmDreamingPhaseStartMarker(normalizedPhase),
                dmDreamingPhaseEndMarker(normalizedPhase),
                body
            )
            File.writeTo(dreamsPath, dmWithTrailingNewline(updated).toArray())
            inlinePath = dreamsPath.toString()
        }

        if (shouldWriteSeparate(config)) {
            let path = dmSeparateReportPath(normalizedPhase, now)
            let title = dmDreamingPhaseHeading(normalizedPhase)["## ".size..]
            let report = "# ${title}\n\n${body}\n"
            File.writeTo(path, report.toArray())
            reportPath = path.toString()
        }

        DreamingMarkdownWriteResult(inlinePath, reportPath)
    }

    public static func writeDeepDreamingReport(
        bodyLines: Array<String>,
        now!: DateTime = DateTime.now()
    ): DreamingMarkdownWriteResult {
        let config = readStorageConfig()
        let body = if (bodyLines.isEmpty()) { "- No durable changes." } else { String.join(bodyLines, delimiter: "\n") }
        let dreamsPath = resolveDreamsPath()
        let original = if (exists(dreamsPath)) { dmReadTextFileOrEmpty(dreamsPath) } else { "" }
        let updated = dmReplaceManagedBlock(
            original,
            dmDreamingPhaseHeading("deep"),
            dmDreamingPhaseStartMarker("deep"),
            dmDreamingPhaseEndMarker("deep"),
            body
        )
        File.writeTo(dreamsPath, dmWithTrailingNewline(updated).toArray())
        var reportPath = ""
        if (shouldWriteSeparate(config)) {
            let path = dmSeparateReportPath("deep", now)
            File.writeTo(path, "# Deep Sleep\n\n${body}\n".toArray())
            reportPath = path.toString()
        }
        DreamingMarkdownWriteResult(dreamsPath.toString(), reportPath)
    }
}

private func normalizeMode(mode: String): String {
    let normalized = mode.trimAscii().toAsciiLower()
    if (normalized == "inline" || normalized == "separate" || normalized == "both") {
        return normalized
    }
    "both"
}

private func shouldWriteInline(config: DreamingMarkdownStorageConfig): Bool {
    config.mode == "inline" || config.mode == "both"
}

private func shouldWriteSeparate(config: DreamingMarkdownStorageConfig): Bool {
    config.mode == "separate" || config.mode == "both" || config.separateReports
}

private func dmDreamingPhaseHeading(phase: String): String {
    match (phase.trimAscii().toAsciiLower()) {
        case "light" => "## Light Sleep"
        case "rem" => "## REM Sleep"
        case "deep" => "## Deep Sleep"
        case _ => "## Dreaming"
    }
}

private func dmDreamingPhaseStartMarker(phase: String): String {
    "<!-- metis:dreaming:${phase.trimAscii().toAsciiLower()}:start -->"
}

private func dmDreamingPhaseEndMarker(phase: String): String {
    "<!-- metis:dreaming:${phase.trimAscii().toAsciiLower()}:end -->"
}

private func dmSeparateReportPath(phase: String, now: DateTime): Path {
    let dir = CliConfig.cwd.join("memory").join("dreaming").join(phase.trimAscii().toAsciiLower())
    if (!exists(dir)) {
        Directory.create(dir, recursive: true)
    }
    dir.join("${now.format("yyyy-MM-dd")}.md")
}
