package metis.cliapp

import metis.core.memory.DreamingPhaseRuntime
import metis.core.memory.MemoryRuntime
import metis.core.memory.MemoryStateRegistry
import metis.core.memory.ShortTermPromotionRuntime
import metis.core.tools.MemoryToolset
import metis.io.PrintUtils

import std.collection.ArrayList
import std.convert.*

private func findFlagValue(parts: Array<String>, flag: String): Option<String> {
    var idx: Int64 = 0
    while (idx + 1 < parts.size) {
        if (parts[idx].trimAscii() == flag) {
            let value = parts[idx + 1].trimAscii()
            if (!value.isEmpty()) {
                return Some(value)
            }
            return None
        }
        idx += 1
    }
    None
}

private func parseIntFlag(parts: Array<String>, flag: String): Option<Int64> {
    match (findFlagValue(parts, flag)) {
        case Some(value) =>
            try {
                Some(Int64.parse(value))
            } catch (_e: Exception) {
                None
            }
        case None => None
    }
}

private func parseFloatFlag(parts: Array<String>, flag: String): Option<Float64> {
    match (findFlagValue(parts, flag)) {
        case Some(value) =>
            try {
                Some(Float64.parse(value))
            } catch (_e: Exception) {
                None
            }
        case None => None
    }
}

private func collectPositionalTail(parts: Array<String>, start: Int64): String {
    let values = ArrayList<String>()
    var idx = start
    while (idx < parts.size) {
        let token = parts[idx].trimAscii()
        if (token.isEmpty()) {
            idx += 1
            continue
        }
        if (token.startsWith("--")) {
            idx += if (idx + 1 < parts.size && !parts[idx + 1].trimAscii().startsWith("--")) { 2 } else { 1 }
            continue
        }
        values.add(token)
        idx += 1
    }
    String.join(values.toArray(), delimiter: " ").trimAscii()
}

private func parseSearchQuery(parts: Array<String>): String {
    match (findFlagValue(parts, "--query")) {
        case Some(value) => value
        case None => collectPositionalTail(parts, 2)
    }
}

private func parseStringFlag(parts: Array<String>, flag: String): Option<String> {
    findFlagValue(parts, flag)
}

protected func isMemoryCommandLine(raw: String): Bool {
    let trimmed = raw.trimAscii()
    trimmed.startsWith("/memory ") || trimmed.startsWith("memory ")
}

protected func handleMemoryLine(raw: String): Unit {
    let trimmed = raw.trimAscii()
    let parts = trimmed.split(" ")
    let deep = trimmed.contains("--deep")
    let agentId = parseStringFlag(parts, "--agent-id")
    let requestedBackend = parseStringFlag(parts, "--backend")
    if (parts.size < 2) {
        PrintUtils.printLine(
            MemoryStateRegistry.statusText(
                agentId: match (agentId) { case Some(value) => value.trimAscii() case None => "" },
                purpose: if (deep) { "cli-status-deep" } else { "cli-status" },
                requestedBackend: match (requestedBackend) { case Some(value) => value.trimAscii() case None => "" },
                deep: deep
            )
        )
        return
    }

    match (parts[1].trimAscii().toAsciiLower()) {
        case "status" =>
            let fix = trimmed.contains("--fix")
            let runIndex = trimmed.contains("--index")
            let deepStatus = deep || runIndex
            let resolvedAgentId = match (agentId) { case Some(value) => value.trimAscii() case None => "" }
            if (fix) {
                PrintUtils.printLine(
                    MemoryStateRegistry.fixArtifacts(
                        agentId: resolvedAgentId,
                        purpose: "cli-fix-artifacts"
                    )
                )
                PrintUtils.printLine("")
            }
            if (runIndex) {
                let indexPath = MemoryStateRegistry.writeIndexSnapshot(
                    agentId: resolvedAgentId,
                    purpose: "cli-write-index-snapshot"
                )
                if (!indexPath.isEmpty()) {
                    PrintUtils.printLine("Memory index written: ${indexPath}")
                    PrintUtils.printLine("")
                }
            }
            if (trimmed.contains("--json")) {
                PrintUtils.printLine(
                    MemoryStateRegistry.statusJson(
                        agentId: resolvedAgentId,
                        purpose: if (deepStatus) { "cli-status-deep" } else { "cli-status" },
                        requestedBackend: match (requestedBackend) { case Some(value) => value.trimAscii() case None => "" },
                        deep: deepStatus
                    )
                )
            } else {
                PrintUtils.printLine(
                    MemoryStateRegistry.statusText(
                        agentId: resolvedAgentId,
                        purpose: if (deepStatus) { "cli-status-deep" } else { "cli-status" },
                        requestedBackend: match (requestedBackend) { case Some(value) => value.trimAscii() case None => "" },
                        deep: deepStatus
                    )
                )
            }
        case "index" =>
            let path = if (trimmed.contains("--force")) {
                MemoryStateRegistry.forceReindex(
                    agentId: match (agentId) { case Some(value) => value.trimAscii() case None => "" },
                    purpose: "cli-force-reindex"
                )
            } else {
                MemoryStateRegistry.writeIndexSnapshot(
                    agentId: match (agentId) { case Some(value) => value.trimAscii() case None => "" },
                    purpose: "cli-write-index-snapshot"
                )
            }
            if (path.isEmpty()) {
                PrintUtils.printLine("Memory index failed.")
            } else {
                PrintUtils.printLine("Memory index written: ${path}")
                PrintUtils.printLine(
                    MemoryStateRegistry.statusText(
                        agentId: match (agentId) { case Some(value) => value.trimAscii() case None => "" },
                        purpose: "cli-status",
                        requestedBackend: match (requestedBackend) { case Some(value) => value.trimAscii() case None => "" }
                    )
                )
            }
        case "search" =>
            let query = parseSearchQuery(parts)
            let maxResults = parseIntFlag(parts, "--max-results")
            let minScore = parseFloatFlag(parts, "--min-score")
            let sessionKey = parseStringFlag(parts, "--session-key")
            if (query.isEmpty()) {
                PrintUtils.printLine("Usage: /memory search <query> [--json] | /memory search --query <text> [--max-results <n>] [--min-score <n>] [--session-key <key>] [--json]")
            } else {
                let out = MemoryToolset.runCliSearch(
                    query,
                    maxResults: maxResults,
                    minScore: minScore,
                    sessionKey: sessionKey,
                    agentId: agentId,
                    json: trimmed.contains("--json")
                )
                PrintUtils.printLine(out)
            }
        case "promote" =>
            let includePromoted = trimmed.contains("--include-promoted")
            let limit = parseIntFlag(parts, "--limit") ?? 8
            let minScore = parseFloatFlag(parts, "--min-score") ?? ShortTermPromotionRuntime.defaultPromotionMinScore()
            let minRecallCount = parseIntFlag(parts, "--min-recall-count") ?? ShortTermPromotionRuntime.defaultPromotionMinRecallCount()
            let minUniqueQueries = parseIntFlag(parts, "--min-unique-queries") ?? ShortTermPromotionRuntime.defaultPromotionMinUniqueQueries()
            let resolvedAgentId = match (agentId) { case Some(value) => value.trimAscii() case None => "" }
            if (parts.size >= 3 && parts[2].trimAscii().toAsciiLower() == "explain") {
                let selector = collectPositionalTail(parts, 3)
                let asJson = trimmed.contains("--json")
                PrintUtils.printLine(MemoryRuntime.explainPromote(
                    selector,
                    json: asJson,
                    limit: limit,
                    includePromoted: includePromoted,
                    minScore: minScore,
                    minRecallCount: minRecallCount,
                    minUniqueQueries: minUniqueQueries,
                    agentId: resolvedAgentId,
                    purpose: "cli-promote-explain"
                ))
            } else {
                let apply = trimmed.contains("--apply")
                let asJson = trimmed.contains("--json")
                if (apply) {
                    PrintUtils.printLine(MemoryRuntime.applyPromote(
                        limit: limit,
                        includePromoted: includePromoted,
                        minScore: minScore,
                        minRecallCount: minRecallCount,
                        minUniqueQueries: minUniqueQueries,
                        agentId: resolvedAgentId,
                        purpose: "cli-promote-apply"
                    ))
                } else if (asJson) {
                    PrintUtils.printLine(MemoryRuntime.previewPromoteJson(
                        limit: limit,
                        includePromoted: includePromoted,
                        minScore: minScore,
                        minRecallCount: minRecallCount,
                        minUniqueQueries: minUniqueQueries,
                        agentId: resolvedAgentId,
                        purpose: "cli-promote-preview-json"
                    ))
                } else {
                    PrintUtils.printLine(MemoryRuntime.previewPromote(
                        limit: limit,
                        includePromoted: includePromoted,
                        minScore: minScore,
                        minRecallCount: minRecallCount,
                        minUniqueQueries: minUniqueQueries,
                        agentId: resolvedAgentId,
                        purpose: "cli-promote-preview"
                    ))
                    PrintUtils.printLine("")
                    PrintUtils.printLine("Use '/memory promote --apply' to append these candidates into MEMORY.md.")
                    PrintUtils.printLine("Use '/memory promote --json' to inspect structured candidates.")
                    PrintUtils.printLine("Use '/memory promote explain <selector> [--json]' to inspect one candidate.")
                    PrintUtils.printLine("Use '--include-promoted' to include already promoted candidates.")
                }
            }
        case "promote-explain" =>
            let includePromoted = trimmed.contains("--include-promoted")
            let selector = collectPositionalTail(parts, 2)
            let asJson = trimmed.contains("--json")
            let limit = parseIntFlag(parts, "--limit") ?? 12
            let minScore = parseFloatFlag(parts, "--min-score") ?? ShortTermPromotionRuntime.defaultPromotionMinScore()
            let minRecallCount = parseIntFlag(parts, "--min-recall-count") ?? ShortTermPromotionRuntime.defaultPromotionMinRecallCount()
            let minUniqueQueries = parseIntFlag(parts, "--min-unique-queries") ?? ShortTermPromotionRuntime.defaultPromotionMinUniqueQueries()
            let resolvedAgentId = match (agentId) { case Some(value) => value.trimAscii() case None => "" }
            PrintUtils.printLine(MemoryRuntime.explainPromote(
                selector,
                json: asJson,
                limit: limit,
                includePromoted: includePromoted,
                minScore: minScore,
                minRecallCount: minRecallCount,
                minUniqueQueries: minUniqueQueries,
                agentId: resolvedAgentId,
                purpose: "cli-promote-explain"
            ))
        case "rem-harness" =>
            let includePromoted = trimmed.contains("--include-promoted")
            let asJson = trimmed.contains("--json")
            let apply = trimmed.contains("--apply")
            let limit = parseIntFlag(parts, "--limit") ?? 6
            let resolvedAgentId = match (agentId) { case Some(value) => value.trimAscii() case None => "" }
            if (apply) {
                PrintUtils.printLine(
                    MemoryRuntime.applyRemHarness(
                        includePromoted: includePromoted,
                        limit: limit,
                        agentId: resolvedAgentId,
                        purpose: "cli-rem-harness-apply"
                    )
                )
            } else {
                PrintUtils.printLine(
                    MemoryRuntime.previewRemHarness(
                        json: asJson,
                        includePromoted: includePromoted,
                        agentId: resolvedAgentId,
                        purpose: "cli-rem-harness-preview"
                    )
                )
            }
        case "dreaming" =>
            let includePromoted = trimmed.contains("--include-promoted")
            if (parts.size >= 3 && parts[2].trimAscii().toAsciiLower() == "status") {
                if (trimmed.contains("--json")) {
                    PrintUtils.printLine(DreamingPhaseRuntime.buildStatusJson())
                } else {
                    PrintUtils.printLine(DreamingPhaseRuntime.buildStatusText())
                }
                return
            }
            if (parts.size >= 3 && parts[2].trimAscii().toAsciiLower() == "reconcile") {
                PrintUtils.printLine(DreamingPhaseRuntime.reconcileManagedCronJobs())
                return
            }
            let phase = if (parts.size >= 4 && parts[2].trimAscii().toAsciiLower() == "register") {
                let v = parts[3].trimAscii().toAsciiLower()
                if (v == "light" || v == "rem" || v == "deep" || v == "all") { v } else { "all" }
            } else if (parts.size >= 4 && parts[2].trimAscii().toAsciiLower() == "sweep") {
                let v = parts[3].trimAscii().toAsciiLower()
                if (v == "light" || v == "rem" || v == "deep" || v == "all") { v } else { "all" }
            } else {
                "all"
            }
            if (parts.size >= 3 && parts[2].trimAscii().toAsciiLower() == "register") {
                let cronExpr = if (trimmed.contains("--cron")) {
                    match (trimmed.indexOf("--cron")) {
                        case Some(idx) =>
                            let tail = trimmed[idx + 6..].trimAscii()
                            let nextOpt = tail.indexOf(" --")
                            match (nextOpt) {
                                case Some(endIdx) => tail[0..endIdx].trimAscii()
                                case None => tail
                            }
                        case None => "0 4 * * *"
                    }
                } else {
                    "0 4 * * *"
                }
                PrintUtils.printLine(DreamingPhaseRuntime.registerManagedCronJobs(phase, cronExpr: cronExpr))
            } else if (parts.size >= 3 && parts[2].trimAscii().toAsciiLower() == "sweep") {
                PrintUtils.printLine(DreamingPhaseRuntime.run(phase, includePromoted: includePromoted))
            } else {
                PrintUtils.printLine("Usage: /memory dreaming status [--json] | reconcile | register [light|rem|deep|all] [--cron '0 4 * * *'] | /memory dreaming sweep [light|rem|deep|all] [--include-promoted]")
            }
        case _ =>
            PrintUtils.printLine("Usage: /memory [status [--json] [--fix] [--deep] [--index]|index [--force]|search <query> [--json] | search --query <text> [--max-results <n>] [--min-score <n>] [--session-key <key>] [--json]|promote [--apply|--json] [--limit <n>] [--min-score <n>] [--min-recall-count <n>] [--min-unique-queries <n>] [--include-promoted]|promote explain <selector> [--json] [--limit <n>] [--include-promoted]|promote-explain <selector> [--json] [--limit <n>] [--include-promoted]|rem-harness [--json|--apply] [--include-promoted]|dreaming status [--json]|dreaming reconcile|dreaming register [light|rem|deep|all] [--cron '0 4 * * *']|dreaming sweep [light|rem|deep|all] [--include-promoted]]")
    }
}
