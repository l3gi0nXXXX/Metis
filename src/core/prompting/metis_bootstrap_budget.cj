package metis.core.prompting

import std.collection.ArrayList

public const DEFAULT_BOOTSTRAP_MAX_CHARS: Int64 = 20000
public const DEFAULT_BOOTSTRAP_TOTAL_MAX_CHARS: Int64 = 150000

private const MIN_BOOTSTRAP_FILE_BUDGET_CHARS: Int64 = 64
private const BOOTSTRAP_HEAD_RATIO_NUMERATOR: Int64 = 7
private const BOOTSTRAP_HEAD_RATIO_DENOMINATOR: Int64 = 10
private const BOOTSTRAP_TAIL_RATIO_NUMERATOR: Int64 = 2
private const BOOTSTRAP_TAIL_RATIO_DENOMINATOR: Int64 = 10
private const MISSING_CONTEXT_FILE_PREFIX = "[MISSING] Expected at:"
private const MEMORY_INDEX_LINE_MAX_CHARS: Int64 = 160
private const MEMORY_MIN_HEAD_CHARS: Int64 = 1024
private const MEMORY_MIN_TAIL_CHARS: Int64 = 256

public class MetisBootstrapTrimResult {
    public var content: String = ""
    public var truncated: Bool = false
    public var maxChars: Int64 = 0
    public var originalLength: Int64 = 0
    public init() {}
}

public class MetisBootstrapBudgetResult {
    public var files: Array<MetisContextFile> = []
    public var warnings: Array<String> = []
    public var totalChars: Int64 = 0
    public var originalTotalChars: Int64 = 0
    public var truncatedFiles: Int64 = 0
    public var missingFiles: Int64 = 0
    public var skippedFiles: Int64 = 0
    public init() {}
}

private func normalizeBootstrapContent(content: String): String {
    content.replace("\r\n", "\n").replace("\r", "\n")
}

private func bootstrapFileLabel(path: String): String {
    let normalized = path.replace("\\", "/").trimAscii()
    if (normalized.isEmpty()) {
        return "context file"
    }
    let pieces = normalized.split("/")
    if (pieces.size == 0) {
        return normalized
    }
    let last = pieces[pieces.size - 1].trimAscii()
    if (last.isEmpty()) {
        return normalized
    }
    last
}

private func bootstrapWarningTrimmed(filePath: String, originalLength: Int64, maxChars: Int64): String {
    "workspace bootstrap file ${bootstrapFileLabel(filePath)} is ${originalLength} chars (limit ${maxChars}); truncating in injected context"
}

private func isMemoryBootstrapPath(path: String): Bool {
    bootstrapFileLabel(path).toAsciiLower() == "memory.md"
}

private func clampBootstrapLine(line: String, maxChars: Int64): String {
    let trimmed = line.trimAscii()
    if (trimmed.isEmpty()) {
        return ""
    }
    if (trimmed.size <= maxChars) {
        return trimmed
    }
    MetisBootstrapBudget.clampToBudget(trimmed, maxChars)
}

private func shouldIncludeMemoryIndexLine(line: String): Bool {
    let trimmed = line.trimAscii()
    if (trimmed.isEmpty()) {
        return false
    }
    if (trimmed.startsWith("#") || trimmed.startsWith("- ") || trimmed.startsWith("* ")) {
        return true
    }
    let upper = trimmed.toAsciiUpper()
    upper.contains("TODO") || upper.contains("NOTE") || upper.contains("FIXME") || upper.contains("IMPORTANT")
}

private func buildMemoryIndexSection(content: String, budget: Int64): String {
    if (budget <= 0) {
        return ""
    }
    let sb = StringBuilder()
    var lineCount: Int64 = 0
    for (line in content.lines()) {
        if (!shouldIncludeMemoryIndexLine(line)) {
            continue
        }
        let compacted = clampBootstrapLine(line, MEMORY_INDEX_LINE_MAX_CHARS)
        if (compacted.isEmpty()) {
            continue
        }
        let entry = "- ${compacted}\n"
        if (sb.size + entry.size > budget) {
            break
        }
        sb.append(entry)
        lineCount += 1
        if (lineCount >= 24) {
            break
        }
    }
    if (sb.size == 0) {
        return ""
    }
    let title = "## Memory Index\n"
    if (title.size + sb.size > budget) {
        return MetisBootstrapBudget.clampToBudget(sb.toString(), budget)
    }
    title + sb.toString()
}

private func trimMemoryContent(content: String, path: String, maxChars: Int64): MetisBootstrapTrimResult {
    let effectiveMax = max(1, maxChars)
    let normalized = normalizeBootstrapContent(content)
    let result = MetisBootstrapTrimResult()
    result.maxChars = effectiveMax
    result.originalLength = normalized.size
    if (normalized.size <= effectiveMax) {
        result.content = normalized
        return result
    }

    let headChars = min(normalized.size, max(MEMORY_MIN_HEAD_CHARS, effectiveMax * 9 / 20))
    let tailChars = min(max(0, normalized.size - headChars), max(MEMORY_MIN_TAIL_CHARS, effectiveMax * 3 / 20))
    let head = normalized[0..headChars]
    let tailStart = max(0, normalized.size - tailChars)
    let tail = normalized[tailStart..normalized.size]
    let marker =
        "\n[...memory bootstrap compressed: kept head, key index, and tail from ${bootstrapFileLabel(path)}; read the source file for full details...]\n"
    let reservedChars = head.size + marker.size + tail.size + 2
    let indexBudget = max(0, effectiveMax - reservedChars)
    let indexSection = buildMemoryIndexSection(normalized, indexBudget)
    let contentWithIndex = if (indexSection.isEmpty()) {
        head + marker + tail
    } else {
        head + "\n" + indexSection + marker + tail
    }
    result.content = MetisBootstrapBudget.clampToBudget(contentWithIndex, effectiveMax)
    result.truncated = true
    result
}

public class MetisBootstrapBudget {
    public static func describe(result: MetisBootstrapBudgetResult): String {
        "bootstrapFiles=${result.files.size}, bootstrapChars=${result.totalChars}, bootstrapOriginalChars=${result.originalTotalChars}, bootstrapTruncatedFiles=${result.truncatedFiles}, bootstrapMissingFiles=${result.missingFiles}, bootstrapSkippedFiles=${result.skippedFiles}, bootstrapWarnings=${result.warnings.size}"
    }

    public static func clampToBudget(content: String, budget: Int64): String {
        let safeBudget = max(0, budget)
        if (safeBudget <= 0) {
            return ""
        }
        if (content.size <= safeBudget) {
            return content
        }
        if (safeBudget <= 1) {
            return content[0..safeBudget]
        }
        content[0..safeBudget - 1] + "…"
    }

    public static func trimContent(content: String, path!: String = "", maxChars!: Int64 = DEFAULT_BOOTSTRAP_MAX_CHARS): MetisBootstrapTrimResult {
        let effectiveMax = max(1, maxChars)
        let normalized = normalizeBootstrapContent(content)
        if (isMemoryBootstrapPath(path) && normalized.size > effectiveMax) {
            return trimMemoryContent(normalized, path, effectiveMax)
        }
        let result = MetisBootstrapTrimResult()
        result.maxChars = effectiveMax
        result.originalLength = normalized.size
        if (normalized.size <= effectiveMax) {
            result.content = normalized
            return result
        }

        let headChars = max(1, effectiveMax * BOOTSTRAP_HEAD_RATIO_NUMERATOR / BOOTSTRAP_HEAD_RATIO_DENOMINATOR)
        let tailChars = max(1, effectiveMax * BOOTSTRAP_TAIL_RATIO_NUMERATOR / BOOTSTRAP_TAIL_RATIO_DENOMINATOR)
        let safeHeadChars = min(headChars, normalized.size)
        let safeTailBudget = max(0, normalized.size - safeHeadChars)
        let safeTailChars = min(tailChars, safeTailBudget)
        let head = normalized[0..safeHeadChars]
        let tailStart = max(0, normalized.size - safeTailChars)
        let tail = normalized[tailStart..normalized.size]
        let fileName = bootstrapFileLabel(path)
        let marker = "\n[...truncated, read ${fileName} for full content...]\n…(truncated ${fileName}: kept ${safeHeadChars}+${safeTailChars} chars of ${normalized.size})…\n"
        result.content = head + marker + tail
        result.truncated = true
        result
    }

    public static func buildContextFiles(
        files: Array<MetisContextFile>,
        maxChars!: Int64 = DEFAULT_BOOTSTRAP_MAX_CHARS,
        totalMaxChars!: Int64 = DEFAULT_BOOTSTRAP_TOTAL_MAX_CHARS
    ): MetisBootstrapBudgetResult {
        let effectiveMaxChars = max(1, maxChars)
        let effectiveTotalMaxChars = max(1, totalMaxChars)
        var remainingTotalChars = effectiveTotalMaxChars
        let result = MetisBootstrapBudgetResult()
        let out = ArrayList<MetisContextFile>()
        let warnings = ArrayList<String>()
        for (file in files) {
            result.originalTotalChars += normalizeBootstrapContent(file.content).size
            if (remainingTotalChars <= 0) {
                result.skippedFiles += 1
                break
            }
            let normalizedPath = file.path.trimAscii()
            if (normalizedPath.isEmpty()) {
                warnings.add("skipping bootstrap file with empty path")
                result.skippedFiles += 1
                continue
            }
            let normalizedContent = normalizeBootstrapContent(file.content)
            if (normalizedContent.startsWith(MISSING_CONTEXT_FILE_PREFIX)) {
                result.missingFiles += 1
                let cappedMissing = MetisBootstrapBudget.clampToBudget(normalizedContent, remainingTotalChars)
                if (cappedMissing.isEmpty()) {
                    result.skippedFiles += 1
                    break
                }
                remainingTotalChars = max(0, remainingTotalChars - cappedMissing.size)
                out.add(MetisContextFile(file.path, cappedMissing))
                continue
            }
            if (remainingTotalChars < MIN_BOOTSTRAP_FILE_BUDGET_CHARS) {
                warnings.add(
                    "remaining bootstrap budget is ${remainingTotalChars} chars (<${MIN_BOOTSTRAP_FILE_BUDGET_CHARS}); skipping additional bootstrap files"
                )
                break
            }
            let fileMaxChars = min(effectiveMaxChars, remainingTotalChars)
            let trimmed = MetisBootstrapBudget.trimContent(normalizedContent, path: file.path, maxChars: fileMaxChars)
            let contentWithinBudget = MetisBootstrapBudget.clampToBudget(trimmed.content, remainingTotalChars)
            if (contentWithinBudget.isEmpty()) {
                result.skippedFiles += 1
                continue
            }
            if (trimmed.truncated || contentWithinBudget.size < trimmed.content.size) {
                result.truncatedFiles += 1
                warnings.add(bootstrapWarningTrimmed(file.path, trimmed.originalLength, trimmed.maxChars))
            }
            remainingTotalChars = max(0, remainingTotalChars - contentWithinBudget.size)
            out.add(MetisContextFile(file.path, contentWithinBudget))
        }
        result.files = out.toArray()
        result.warnings = warnings.toArray()
        result.totalChars = effectiveTotalMaxChars - remainingTotalChars
        result
    }
}
