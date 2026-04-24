package metis.core.memory

import magic.prelude.*

import metis.core.config.CliConfig
import metis.cron.executeGatewayCronCommand
import magic.log.LogUtils

import std.collection.ArrayList
import std.collection.HashSet
import std.convert.*
import std.fs.{Directory, File, exists, Path}
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private let DEFAULT_LIGHT_CRON = "0 2 * * *"
private let DEFAULT_REM_CRON = "0 4 * * *"
private let DEFAULT_DEEP_CRON = "0 5 * * *"

private func dreamingNowMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000
}

private func phaseConfigDir(): Path {
    let dir = CliConfig.dotDir.join("memory")
    if (!exists(dir)) {
        Directory.create(dir, recursive: true)
    }
    dir
}

private func normalizePhaseName(phase: String): String {
    let normalized = phase.trimAscii().toAsciiLower()
    if (normalized == "light" || normalized == "rem" || normalized == "deep" || normalized == "all") {
        return normalized
    }
    "all"
}

private func phaseStatusRows(config: JsonObject): JsonArray {
    let rows = JsonArray([])
    for (name in ["light", "rem", "deep"]) {
        let row = JsonObject()
        row.put("name", JsonString(name))
        match (config.get(name)) {
            case Some(obj: JsonObject) =>
                row.put("enabled", dreamingGetJsonBoolValue(obj, "enabled", true).toJsonValue())
                row.put("cron", JsonString(dreamingGetJsonStringValue(obj, "cron", "")))
                row.put("limit", dreamingGetJsonInt64Value(obj, "limit", 6).toJsonValue())
                row.put("lookbackDays", dreamingGetJsonInt64Value(obj, "lookbackDays", 14).toJsonValue())
                row.put("workspaceDir", JsonString(dreamingGetJsonStringValue(obj, "workspaceDir", CliConfig.cwd.toString())))
            case _ =>
                row.put("enabled", true.toJsonValue())
                row.put("cron", JsonString(""))
                row.put("limit", 6.toJsonValue())
                row.put("lookbackDays", 14.toJsonValue())
                row.put("workspaceDir", JsonString(CliConfig.cwd.toString()))
        }
        rows.add(row)
    }
    rows
}

private func dreamingGetJsonStringValue(obj: JsonObject, key: String, fallback: String): String {
    match (obj.get(key)) {
        case Some(s: JsonString) => s.getValue()
        case _ => fallback
    }
}

private func dreamingGetJsonInt64Value(obj: JsonObject, key: String, fallback: Int64): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            try {
                Int64.parse(v.toString())
            } catch (_e: Exception) {
                fallback
            }
        case _ => fallback
    }
}

private func dreamingGetJsonBoolValue(obj: JsonObject, key: String, fallback: Bool): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try {
                v.asBool().getValue()
            } catch (_e: Exception) {
                fallback
            }
        case _ => fallback
    }
}

private func phaseCronName(phase: String): String {
        match (phase) {
        case "light" => MemoryRuntime.DREAMING_LIGHT_CRON_NAME
        case "rem" => MemoryRuntime.DREAMING_REM_CRON_NAME
        case "deep" => "Memory Deep Dreaming"
        case _ => MemoryRuntime.DREAMING_CRON_NAME
    }
}

private func phaseSystemEvent(phase: String): String {
        match (phase) {
        case "light" => MemoryRuntime.DREAMING_LIGHT_SYSTEM_EVENT
        case "rem" => MemoryRuntime.DREAMING_REM_SYSTEM_EVENT
        case "deep" => "__magic_cli_memory_dreaming_deep__"
        case _ => MemoryRuntime.DREAMING_SYSTEM_EVENT
    }
}

private func defaultPhaseConfig(phase: String): JsonObject {
    let root = JsonObject()
    root.put("enabled", true.toJsonValue())
    root.put("workspaceDir", JsonString(CliConfig.cwd.toString()))
    match (phase) {
        case "light" =>
            root.put("cron", JsonString(DEFAULT_LIGHT_CRON))
            root.put("limit", 6.toJsonValue())
            root.put("lookbackDays", 14.toJsonValue())
        case "rem" =>
            root.put("cron", JsonString(DEFAULT_REM_CRON))
            root.put("limit", 6.toJsonValue())
            root.put("lookbackDays", 14.toJsonValue())
        case "deep" =>
            root.put("cron", JsonString(DEFAULT_DEEP_CRON))
            root.put("limit", 6.toJsonValue())
            root.put("lookbackDays", 21.toJsonValue())
        case _ =>
            root.put("cron", JsonString(""))
            root.put("limit", 6.toJsonValue())
            root.put("lookbackDays", 14.toJsonValue())
    }
    root
}

private func defaultDreamingConfig(): JsonObject {
    let root = JsonObject()
    root.put("version", 1.toJsonValue())
    root.put("workspaces", JsonArray([JsonString(CliConfig.cwd.toString())]))
    root.put("light", defaultPhaseConfig("light"))
    root.put("rem", defaultPhaseConfig("rem"))
    root.put("deep", defaultPhaseConfig("deep"))
    root
}

private func mergePhaseConfig(raw: JsonObject, phase: String): JsonObject {
    let merged = defaultPhaseConfig(phase)
    let defaults = defaultPhaseConfig(phase)
    let fallbackCron = dreamingGetJsonStringValue(defaults, "cron", "")
    let fallbackLimit = dreamingGetJsonInt64Value(defaults, "limit", 6)
    let fallbackLookback = dreamingGetJsonInt64Value(defaults, "lookbackDays", 14)
    merged.put("enabled", dreamingGetJsonBoolValue(raw, "enabled", true).toJsonValue())
    merged.put("workspaceDir", JsonString(dreamingGetJsonStringValue(raw, "workspaceDir", CliConfig.cwd.toString())))
    merged.put("cron", JsonString(dreamingGetJsonStringValue(raw, "cron", fallbackCron)))
    merged.put("limit", dreamingGetJsonInt64Value(raw, "limit", fallbackLimit).toJsonValue())
    merged.put("lookbackDays", dreamingGetJsonInt64Value(raw, "lookbackDays", fallbackLookback).toJsonValue())
    merged
}

private func normalizeDreamingConfig(raw: JsonObject): JsonObject {
    let root = defaultDreamingConfig()
    match (raw.get("workspaces")) {
        case Some(arr) =>
            let out = JsonArray([])
            let seen = HashSet<String>()
            var addedAny = false
            for (item in arr.asArray().getItems()) {
                match (item) {
                    case s: JsonString =>
                        let value = s.getValue().trimAscii()
                        if (!value.isEmpty() && !seen.contains(value)) {
                            seen.add(value)
                            out.add(JsonString(value))
                            addedAny = true
                        }
                    case _ => ()
                }
            }
            if (!addedAny) {
                out.add(JsonString(CliConfig.cwd.toString()))
            }
            root.put("workspaces", out)
        case _ => ()
    }
    for (phase in ["light", "rem", "deep"]) {
        match (raw.get(phase)) {
            case Some(obj: JsonObject) => root.put(phase, mergePhaseConfig(obj, phase))
            case _ => root.put(phase, defaultPhaseConfig(phase))
        }
    }
    root
}

public class DreamingPhaseRuntime {
    public static func configPath(): Path {
        phaseConfigDir().join("dreaming-phases.json")
    }

    public static func readConfig(): JsonObject {
        let path = configPath()
        if (!exists(path)) {
            return defaultDreamingConfig()
        }
        try {
            match (JsonValue.fromStr(String.fromUtf8(File.readFrom(path)))) {
                case obj: JsonObject => normalizeDreamingConfig(obj)
                case _ => defaultDreamingConfig()
            }
        } catch (_e: Exception) {
            defaultDreamingConfig()
        }
    }

    public static func writeConfig(config: JsonObject): String {
        let normalized = normalizeDreamingConfig(config)
        let path = configPath()
        File.writeTo(path, normalized.toJsonString().toArray())
        path.toString()
    }

    public static func fixArtifacts(): Array<String> {
        let fixes = ArrayList<String>()
        let path = configPath()
        if (!exists(path)) {
            fixes.add("created dreaming phase config: ${writeConfig(defaultDreamingConfig())}")
        } else {
            fixes.add("normalized dreaming phase config: ${writeConfig(readConfig())}")
        }
        fixes.toArray()
    }

    public static func buildStatusJson(): String {
        let config = readConfig()
        let root = JsonObject()
        root.put("status", JsonString("ok"))
        root.put("action", JsonString("memory_dreaming_status"))
        root.put("configPath", JsonString(configPath().toString()))
        root.put("configPresent", exists(configPath()).toJsonValue())
        root.put("phases", phaseStatusRows(config))
        root.put("markdown", JsonValue.fromStr(DreamingMarkdownRuntime.buildStatusJson()))
        root.put("dailyIngestion", JsonValue.fromStr(DailyIngestionRuntime.buildStatusSummaryJson()))
        root.toJsonString()
    }

    public static func configuredWorkspaces(): Array<String> {
        let config = readConfig()
        let out = ArrayList<String>()
        match (config.get("workspaces")) {
            case Some(arr) =>
                for (item in arr.asArray().getItems()) {
                    match (item) {
                        case s: JsonString =>
                            let value = s.getValue().trimAscii()
                            if (!value.isEmpty()) {
                                out.add(value)
                            }
                        case _ => ()
                    }
                }
            case _ => ()
        }
        if (out.isEmpty()) {
            out.add(CliConfig.cwd.toString())
        }
        out.toArray()
    }

    public static func run(phase: String, includePromoted!: Bool = false): String {
        let normalized = normalizePhaseName(phase)
        if (normalized == "all") {
            return runAll(includePromoted: includePromoted)
        }
        let config = readConfig()
        let phaseCfg = match (config.get(normalized)) {
            case Some(obj: JsonObject) => mergePhaseConfig(obj, normalized)
            case _ => defaultPhaseConfig(normalized)
        }
        if (!dreamingGetJsonBoolValue(phaseCfg, "enabled", true)) {
            return "Dreaming phase '${normalized}' is disabled in ${configPath()}."
        }
        let limit = max(1, dreamingGetJsonInt64Value(phaseCfg, "limit", 6))
        let lookback = max(1, dreamingGetJsonInt64Value(phaseCfg, "lookbackDays", if (normalized == "deep") { 21 } else { 14 }))
        match (normalized) {
            case "light" => MemoryRuntime.applyLightDreaming(
                includePromoted: includePromoted,
                limit: limit,
                lookbackDays: lookback,
                purpose: "dreaming-phase-light"
            )
            case "rem" => MemoryRuntime.applyRemHarness(
                includePromoted: includePromoted,
                limit: limit,
                lookbackDays: lookback,
                purpose: "dreaming-phase-rem"
            )
            case "deep" => MemoryRuntime.applyDeepDreaming(
                includePromoted: includePromoted,
                limit: limit,
                lookbackDays: lookback,
                purpose: "dreaming-phase-deep"
            )
            case _ => MemoryRuntime.applyDreamingSweep(includePromoted: includePromoted, purpose: "dreaming-phase-all")
        }
    }

    public static func runAll(includePromoted!: Bool = false): String {
        let outputs = ArrayList<String>()
        for (phase in ["light", "rem", "deep"]) {
            outputs.add(run(phase, includePromoted: includePromoted))
        }
        "Memory dreaming sweep completed.\n" + String.join(outputs.toArray(), delimiter: "\n")
    }

    public static func registerManagedCronJobs(phase: String, cronExpr!: String = ""): String {
        let normalized = normalizePhaseName(phase)
        let outputs = ArrayList<String>()
        let phases = if (normalized == "all") { ["light", "rem", "deep"] } else { [normalized] }
        let config = readConfig()
        for (name in phases) {
            let phaseCfg = match (config.get(name)) {
                case Some(obj: JsonObject) => mergePhaseConfig(obj, name)
                case _ => defaultPhaseConfig(name)
            }
            if (!dreamingGetJsonBoolValue(phaseCfg, "enabled", true)) {
                outputs.add("Dreaming phase '${name}' disabled; skipped cron registration.")
                continue
            }
            let desiredCron = if (!cronExpr.trimAscii().isEmpty()) { cronExpr.trimAscii() } else { dreamingGetJsonStringValue(phaseCfg, "cron", "") }
            if (name == "deep") {
                outputs.add("Deep dreaming registered in config only; runtime cron uses manual or system-event trigger in this build.")
                continue
            }
            let phaseLimit = dreamingGetJsonInt64Value(phaseCfg, "limit", 6)
            let phaseLookback = dreamingGetJsonInt64Value(phaseCfg, "lookbackDays", 14)
            let (out, _ec) = executeGatewayCronCommand([
                "cron",
                "add",
                "--name", phaseCronName(name),
                "--cron", desiredCron,
                "--session", "main",
                "--system-event", phaseSystemEvent(name),
                "--wake-mode", "next-heartbeat",
                "--message", "Run managed memory ${name} dreaming sweep"
            ])
            outputs.add(out)
        }
        String.join(outputs.toArray(), delimiter: "\n")
    }

    public static func reconcileManagedCronJobs(): String {
        let startMs = dreamingNowMs()
        let outputs = ArrayList<String>()
        let lightStartMs = dreamingNowMs()
        outputs.add(registerManagedCronJobs("light"))
        LogUtils.info("Gateway.dreaming.timing: step=reconcile-light elapsedMs=${dreamingNowMs() - lightStartMs}")
        let remStartMs = dreamingNowMs()
        outputs.add(registerManagedCronJobs("rem"))
        LogUtils.info("Gateway.dreaming.timing: step=reconcile-rem elapsedMs=${dreamingNowMs() - remStartMs}")
        LogUtils.info("Gateway.dreaming.timing: step=reconcile-total elapsedMs=${dreamingNowMs() - startMs}")
        String.join(outputs.toArray(), delimiter: "\n")
    }

    public static func handleSystemEvent(systemEvent: String, includePromoted!: Bool = false): Option<String> {
        let normalized = systemEvent.trimAscii()
        if (normalized.isEmpty()) {
            return None
        }
        if (normalized == MemoryRuntime.DREAMING_LIGHT_SYSTEM_EVENT) {
            return Some(run("light", includePromoted: includePromoted))
        }
        if (normalized == MemoryRuntime.DREAMING_REM_SYSTEM_EVENT) {
            return Some(run("rem", includePromoted: includePromoted))
        }
        if (normalized == MemoryRuntime.DREAMING_SYSTEM_EVENT) {
            return Some(runAll(includePromoted: includePromoted))
        }
        if (normalized == "__magic_cli_memory_dreaming_deep__") {
            return Some(run("deep", includePromoted: includePromoted))
        }
        None
    }
}
