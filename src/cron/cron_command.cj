package metis.cron

import metis.core.config.CliConfig
import metis.core.config.CliSettingManager

import std.collection.ArrayList
import std.convert.Parsable
import std.fs.Path
import std.sort.sort
import std.sync.Mutex
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject, JsonString, JsonValue}

private let gatewayCronRunHookLock = Mutex()
private var gatewayCronRunHook: Option<(Array<String>) -> (String, Int64)> = None<(Array<String>) -> (String, Int64)>

/**
 * 由 `metis.gateway.runtime` 在构建网关时注册，使 IM `/cron run` 可走与 `CronRunner` 同源路径（避免 `gateway.core` 直接依赖 `gateway.runtime` 形成环）。
 */
public func registerGatewayCronRunUnified(hook: (Array<String>) -> (String, Int64)): Unit {
    synchronized(gatewayCronRunHookLock) {
        gatewayCronRunHook = Some(hook)
    }
}

/**
 * 将 `/cron ...` 整行解析为与 `gateway cron` 相同的参数数组（首元素为 `cron`）。
 * 若不是 `/cron` 前缀则返回空数组。
 */
public func parseSlashCronLine(raw: String): Array<String> {
    let t = raw.trimAscii()
    let low = t.toAsciiLower()
    if (low != "/cron" && !low.startsWith("/cron ")) {
        return Array<String>()
    }
    let tail = if (t.size <= 5) {
        ""
    } else {
        t[5..].trimAscii()
    }
    let parts = ArrayList<String>()
    parts.add("cron")
    if (!tail.isEmpty()) {
        for (seg in tail.split(" ")) {
            let one = seg.trimAscii()
            if (!one.isEmpty()) {
                parts.add(one)
            }
        }
    }
    parts.toArray()
}

/** 与 CLI `gateway cron`、交互式 `/cron`、IM 内 `/cron` 共用，返回输出文本与进程退出码。 */
public func executeGatewayCronCommand(sub: Array<String>): (String, Int64) {
    if (sub.size < 1 || sub[0].trimAscii().toAsciiLower() != "cron") {
        return cronErr("invalid cron command: first token must be cron")
    }
    if (sub.size < 2) {
        return (cronHelpText(), 0)
    }
    match (tryCronSubcommandHelpFromArgv(sub)) {
        case Some(pair) => return pair
        case None => ()
    }
    let path = cronStorePath(CliConfig.dotDir)
    let cmd = sub[1].trimAscii().toAsciiLower()
    if (cmd == "help" || cmd == "-h" || cmd == "--help") {
        return (cronHelpText(), 0)
    }
    if (cmd == "path") {
        return (path.toString(), 0)
    }
    if (cmd == "status") {
        if (cronArgvHasJsonFlag(sub, 2)) {
            return cronCmdStatusJson(path)
        }
        return cronCmdStatus(path)
    }
    if (cmd == "list") {
        return cronCmdList(path, sub)
    }
    if (cmd == "add" || cmd == "create") {
        return cronCmdAdd(path, sub)
    }
    if (cmd == "remove" || cmd == "rm" || cmd == "delete") {
        return cronCmdRemove(path, sub)
    }
    if (cmd == "enable") {
        return cronCmdSetEnabled(path, sub, true)
    }
    if (cmd == "disable") {
        return cronCmdSetEnabled(path, sub, false)
    }
    if (cmd == "edit") {
        return cronCmdEdit(path, sub)
    }
    if (cmd == "update") {
        return cronCmdUpdate(path, sub)
    }
    if (cmd == "run") {
        synchronized(gatewayCronRunHookLock) {
            match (gatewayCronRunHook) {
                case Some(f) => return f(sub)
                case None => ()
            }
        }
        return cronErr(
            "cron run 尚未注册网关执行器：请先启动 gateway serve，或使用 `gateway cron run`（会自行拉起网关执行一次）。"
        )
    }
    if (cmd == "runs") {
        return cronCmdRuns(path, sub)
    }
    if (cmd == "wake") {
        return cronCmdWake(path, sub)
    }
    return cronErr("invalid cron command: unknown subcommand")
}

private func cronErr(message: String): (String, Int64) {
    ("Cron command failed\nError: ${message}", 1)
}

private func cronHelpText(): String {
    "Metis gateway cron\n" +
        "Inspect and manage scheduled jobs.\n" +
        "\n" +
        "Docs:\n" +
        "https://docs.metis.ai/zh-CN/automation/cron-jobs\n" +
        "\n" +
        "Examples:\n" +
        "  gateway cron add --name <jobId> --every <milliseconds|30s|5m|1h|2d> --session main|isolated|current|session:xxx --message <text...>\n" +
        "  gateway cron add --name <jobId> --at <unix-ms|unix-seconds|iso8601|relative-20m> --session ... --message <text...>\n" +
        "  gateway cron update --job-id <jobId> --enabled true|false\n" +
        "  gateway cron update --job-id <jobId> --message <new-prompt...>\n" +
        "  gateway cron run --job-id <jobId>\n" +
        "  gateway cron runs [--job-id <jobId>]\n" +
        "  gateway cron wake [--job-id <jobId>] [--mode now|next-heartbeat]\n" +
        "  gateway cron status | list [--all] | path | remove <jobId> | remove --id <jobId>\n" +
        "  Aliases: create -> add, delete/rm -> remove.\n" +
        "  gateway cron run <jobId> | run --job-id <jobId> [--due]  (--due only triggers when the job is due; exit code 1 means not due yet)\n" +
        "  gateway cron add ... [--timeout-ms|--timeout-seconds] [--stagger 30s|--exact] (cron schedules only) [--wake now|next-heartbeat]\n" +
        "  gateway cron update --job-id <jobId> [--stagger|--exact] [--timeout-seconds] ...\n" +
        "  gateway cron add ... [--max-retries 2] [--retry-backoff-ms 1000]\n" +
        "  gateway cron update --job-id <jobId> [--failure-channel feishu] [--failure-to <chat_id>] [--failure-announce]\n" +
        "  add/update also supports: --description --delete-after-run --agent-id --session-key --model --thinking-level --light-context\n" +
        "  --delivery-account-id --best-effort-deliver --failure-account-id --failure-alert-after N --failure-alert-cooldown-ms N\n" +
        "\n" +
        "Notes:\n" +
        "  session selects the execution target.\n" +
        "  Use --channel and --to to deliver job output through the gateway.\n" +
        "  Use --announce to prefix delivered output with the cron job id.\n" +
        "  Use --system-event and --wake-mode for scheduling metadata and wake hints.\n" +
        "\n" +
        "  gateway cron add --name <id> --cron \"minute hour day month weekday\" [--tz UTC+8] ... --message <text>\n" +
        "  gateway cron add ... [--channel feishu] [--to <chat_id>] [--announce]\n" +
        "\n" +
        "Important: the runtime root defaults to `~/.metis`, and cron state is stored there.\n" +
        "To override the runtime root, set:\n" +
        "  METIS_HOME=<absolute path to the Metis data directory>\n" +
        "It should match the path reported by `gateway cron path`.\n" +
        "\n" +
        "Subcommand help:\n" +
        "  gateway cron add --help\n" +
        "  gateway cron update --help\n" +
        "  gateway cron edit --help\n" +
        "  gateway cron remove --help\n" +
        "  gateway cron run --help\n" +
        "  gateway cron list --help\n" +
        "  gateway cron runs --help\n" +
        "  gateway cron wake --help\n" +
        "  gateway cron enable --help\n" +
        "  gateway cron disable --help\n"
}

/** 自 `fromIdx` 起是否出现 `-h` / `--help`（与当前子命令级 help 约定一致）。 */
private func cronArgvHasHelpFlag(sub: Array<String>, fromIdx: Int64): Bool {
    var i = fromIdx
    while (i < sub.size) {
        let t = sub[i].trimAscii().toAsciiLower()
        if (t == "--help" || t == "-h") {
            return true
        }
        i += 1
    }
    false
}

private func cronArgvHasJsonFlag(sub: Array<String>, fromIdx: Int64): Bool {
    var i = fromIdx
    while (i < sub.size) {
        if (sub[i].trimAscii().toAsciiLower() == "--json") {
            return true
        }
        i += 1
    }
    false
}

private func cronNormalizeCronSubcommandForHelp(raw: String): String {
    let c = raw.trimAscii().toAsciiLower()
    if (c == "create") {
        return "add"
    }
    if (c == "rm" || c == "delete") {
        return "remove"
    }
    c
}

private func cronSubcommandHelpText(subCmdNorm: String): String {
    if (subCmdNorm == "add") {
        return "Usage: gateway cron add [options]\n" +
            "\n" +
            "Add a cron job.\n" +
            "\n" +
            "Options:\n" +
            "  --name, -n <id>              Job id (required)\n" +
            "  --every <dur|ms>             Interval: 30s, 5m, 1h, 2d or milliseconds\n" +
            "  --at <when>                  One-shot: Unix ms, ISO8601, or relative e.g. 20m\n" +
            "  --cron <expr>                Five-field cron expression (use quotes if spaces)\n" +
            "  --tz <zone>                  Time zone: UTC±, UTC+8, or common IANA e.g. Asia/Shanghai\n" +
            "  --session <target>           main | isolated | current | session:<key>\n" +
            "  --message, -m <text>         Prompt for the agent (required; consumes rest of argv)\n" +
            "  --system-event <name>        Optional event label\n" +
            "  --wake-mode, --wake <mode>   Wake scheduling hint, e.g. now | next-heartbeat\n" +
            "  --channel <name>             Delivery adapter (e.g. feishu)\n" +
            "  --to <peer>                  Delivery peer / chat id\n" +
            "  --announce                   Prefix delivered body with [cron:<id>]\n" +
            "  --timeout-ms <n>             Agent reply timeout in ms (0 = no limit)\n" +
            "  --timeout-seconds <n>        Same as timeout-ms = n * 1000\n" +
            "  --stagger <dur|ms>           With --cron only; jitter window\n" +
            "  --exact                      With --cron: stagger 0\n" +
            "  --max-retries <n>            Extra retries after failure (>=0)\n" +
            "  --retry-backoff-ms <n>       Base backoff between retries (ms)\n" +
            "  --failure-channel <name>     Channel for failure notifications\n" +
            "  --failure-to <peer>          Target peer for failure path\n" +
            "  --failure-announce           Send failure text to IM (default on)\n" +
            "  --no-failure-announce        Disable failure announce\n" +
            "  --description <text>         Human note stored with the job\n" +
            "  --delete-after-run           Remove the job after a successful run\n" +
            "  --no-delete-after-run\n" +
            "  --agent, --agent-id <id>     Agent id hint\n" +
            "  --session-key <key>          Override the conversation key for execution\n" +
            "  --model, --model-override <id>  Model id hint\n" +
            "  --thinking-level <level>     Thinking depth hint\n" +
            "  --light-context              Prefer smaller context\n" +
            "  --no-light-context\n" +
            "  --delivery-account-id <id>   Multi-account delivery id\n" +
            "  --best-effort-deliver        Do not fail the job if delivery fails\n" +
            "  --failure-account-id <id>    Account for the failure channel\n" +
            "  --failure-alert-after <n>    Failures before alerting\n" +
            "  --failure-alert-cooldown-ms <n>  Minimum ms between failure alerts\n" +
            "\n" +
            "Choose exactly one of --every, --at, or --cron.\n" +
            "Alias: create -> add.\n"
    }
    if (subCmdNorm == "update") {
        return "Usage: gateway cron update --job-id <id> [options]\n" +
            "   or: gateway cron update --id <id> [options]\n" +
            "\n" +
            "Patch fields on an existing job. At least one patch flag is required.\n" +
            "After a schedule change, nextRunAtMs is recomputed from the new schedule.\n" +
            "\n" +
            "Options:\n" +
            "  --job-id, --id <id>          Job id (required)\n" +
            "  --enabled <true|false>     Turn job on or off\n" +
            "  --message, -m <text>       New agent prompt (consumes rest of argv)\n" +
            "  --session <target>        main | isolated | current | session:<key>\n" +
            "  --every <dur|ms>           Replace schedule with interval (mutually exclusive with --at/--cron per call)\n" +
            "  --at <when>                Replace schedule with one-shot time (same formats as add)\n" +
            "  --cron <expr>              Replace schedule with five-field expr (single token; quote if needed)\n" +
            "  --tz <zone>                With --cron or to retime-zone existing cron schedule\n" +
            "  --system-event <name>      Optional event label\n" +
            "  --wake-mode, --wake <mode> Wake scheduling hint\n" +
            "  --channel <name>           Delivery adapter (e.g. feishu)\n" +
            "  --to <peer>                Delivery peer / chat id\n" +
            "  --announce                 Enable delivery body prefix [cron:<id>]\n" +
            "  --no-announce              Disable delivery announce prefix\n" +
            "  --timeout-ms <n>           Agent reply timeout ms (0 = no limit)\n" +
            "  --timeout-seconds <n>      Same as timeout-ms = n * 1000\n" +
            "  --stagger <dur|ms>         Cron only: jitter window (not valid with --every/--at)\n" +
            "  --exact                    Cron only: stagger 0\n" +
            "  --max-retries <n>          Retry count after failure\n" +
            "  --retry-backoff-ms <n>     Backoff base between retries\n" +
            "  --failure-channel <name>   Failure notification channel\n" +
            "  --failure-to <peer>        Failure notification target\n" +
            "  --failure-announce         Send failure to IM (default if not toggled)\n" +
            "  --no-failure-announce      Disable failure announce\n" +
            "  --description <text>       Human note stored with the job\n" +
            "  --delete-after-run         Remove the job after a successful run\n" +
            "  --no-delete-after-run\n" +
            "  --agent, --agent-id <id>   Agent id hint\n" +
            "  --session-key <key>        Override the conversation key for execution\n" +
            "  --model, --model-override <id>  Model id hint\n" +
            "  --thinking-level <level>   Thinking depth hint\n" +
            "  --light-context            Prefer smaller context\n" +
            "  --no-light-context\n" +
            "  --delivery-account-id <id> Delivery account id\n" +
            "  --best-effort-deliver      Do not fail the job if delivery fails\n" +
            "  --no-best-effort-deliver\n" +
            "  --failure-account-id <id>  Failure account id\n" +
            "  --failure-alert-after <n>  Failures before alerting\n" +
            "  --failure-alert-cooldown-ms <n>  Minimum ms between failure alerts\n" +
            "\n" +
            "Schedule: pass at most one of --every, --at, or --cron in a single update.\n" +
            "Do not combine --stagger/--exact with --every or --at.\n"
    }
    if (subCmdNorm == "edit") {
        return "Usage: gateway cron edit <jobId> [options]\n" +
            "\n" +
            "Lightweight edit: only toggles enabled state or replaces the prompt.\n" +
            "Does not change schedule, delivery, retries, or other extension fields.\n" +
            "For those, use: gateway cron update --help\n" +
            "\n" +
            "Arguments:\n" +
            "  <jobId>                    Job id (first positional token after `edit`)\n" +
            "\n" +
            "Options:\n" +
            "  --enabled <true|false>     true | false | 1 | 0 | yes | no\n" +
            "  --message, -m <text>       New prompt (consumes rest of argv)\n" +
            "\n" +
            "You must pass at least one of --enabled or --message.\n"
    }
    if (subCmdNorm == "remove") {
        return "Usage: gateway cron remove <id>\n" +
            "   or: gateway cron remove --job-id <id>\n" +
            "   or: gateway cron remove --id <id>\n" +
            "\n" +
            "Delete one job from the store (JSON file). Idempotent: missing id returns removed:false.\n" +
            "\n" +
            "Arguments:\n" +
            "  <id>                       Job id when using positional form\n" +
            "\n" +
            "Options:\n" +
            "  --job-id, --id <id>        Same as positional id\n" +
            "\n" +
            "Aliases: rm, delete.\n"
    }
    if (subCmdNorm == "run") {
        return "Usage: gateway cron run <jobId> [options]\n" +
            "   or: gateway cron run --job-id <id> [options]\n" +
            "   or: gateway cron run --id <id> [options]\n" +
            "\n" +
            "Execute one job immediately through the cron runner.\n" +
            "\n" +
            "Arguments:\n" +
            "  <jobId>                    Job id when given as first token after `run`\n" +
            "\n" +
            "Options:\n" +
            "  --job-id, --id <id>        Job id (alternative to positional)\n" +
            "  --due                      Run only when the job is due; exit code 1 if it is not due yet\n"
    }
    if (subCmdNorm == "list") {
        return "Usage: gateway cron list [options]\n" +
            "\n" +
            "List cron jobs in a human-readable table. Use --json for machine output.\n" +
            "\n" +
            "Options:\n" +
            "  --json                     Print JSON instead of text\n" +
            "  --all                      Synonym for --include-disabled\n" +
            "  --include-disabled         List disabled jobs too (default: only enabled)\n" +
            "  --limit <n>                Max jobs to return (default 50, min 1)\n" +
            "  --offset <n>               Skip first n jobs after filter (default 0)\n"
    }
    if (subCmdNorm == "runs") {
        return "Usage: gateway cron runs [options]\n" +
            "\n" +
            "Print run log in a human-readable table. Use --json for machine output.\n" +
            "Without --job-id: merge entries from all jobs, sort by ts descending, then paginate.\n" +
            "\n" +
            "Options:\n" +
            "  --json                     Print JSON instead of text\n" +
            "  --job-id, --id <id>        Only runs for this job id\n" +
            "  --limit <n>                Page size (default 50)\n" +
            "  --offset <n>               Skip entries (default 0)\n"
    }
    if (subCmdNorm == "wake") {
        return "Usage: gateway cron wake [options]\n" +
            "\n" +
            "Bump nextRunAtMs for matching enabled jobs: immediate (mode=now) or near-future (mode=next-heartbeat).\n" +
            "This updates scheduling only. Use `cron run` to execute the job.\n" +
            "\n" +
            "Options:\n" +
            "  --job-id, --id <id>        Only touch this job id (optional; default: all enabled jobs)\n" +
            "  --mode <now|next-heartbeat>  Default: now\n" +
            "  --text <hint>                Optional reason text\n"
    }
    if (subCmdNorm == "enable" || subCmdNorm == "disable") {
        let verb = subCmdNorm
        return "Usage: gateway cron ${verb} <id>\n" +
            "\n" +
            "Set the job's enabled flag and persist the store.\n" +
            "\n" +
            "Arguments:\n" +
            "  <id>                       Job id (positional, required)\n"
    }
    if (subCmdNorm == "path") {
        return "Usage: gateway cron path\n" +
            "\n" +
            "Print the absolute path to the cron job store file.\n"
    }
    if (subCmdNorm == "status") {
        return "Usage: gateway cron status [--json]\n" +
            "\n" +
            "Print cron runtime status as text. Use --json for machine output.\n"
    }
    if (subCmdNorm == "help") {
        return cronHelpText()
    }
    "Unknown subcommand '${subCmdNorm}'.\n" +
        "Try: gateway cron --help\n" +
        "Or:  gateway cron <add|update|edit|remove|run|list|runs|wake|...> --help\n"
}

/**
 * 识别 `cron <subcommand> ... --help` / `-h`（任意位置自 argv[2] 起），供 `executeGatewayCronCommand` 与
 * `gatewayExecuteCronWithUnifiedRun`（避免 `run` 抢先走统一执行）共用。
 */
public func tryCronSubcommandHelpFromArgv(sub: Array<String>): Option<(String, Int64)> {
    if (sub.size < 2 || sub[0].trimAscii().toAsciiLower() != "cron") {
        return None<(String, Int64)>
    }
    if (sub.size >= 3 && cronArgvHasHelpFlag(sub, 2)) {
        let scNorm = cronNormalizeCronSubcommandForHelp(sub[1])
        return Some((cronSubcommandHelpText(scNorm), 0))
    }
    None<(String, Int64)>
}

private func cronCmdStatus(path: Path): (String, Int64) {
    let jobs = cronLoadOrEmpty(path)
    var nextWakeAtMsText = "null"
    var nextWakeAtMs: Int64 = 0
    for (j in jobs) {
        if (!j.enabled) {
            continue
        }
        let nxt = j.state.nextRunAtMs
        if (nxt <= 0) {
            continue
        }
        if (nextWakeAtMs <= 0 || nxt < nextWakeAtMs) {
            nextWakeAtMs = nxt
        }
    }
    if (nextWakeAtMs > 0) {
        nextWakeAtMsText = "${nextWakeAtMs}"
    }
    let cronEnabled = CliSettingManager.readGatewaySettings().enabled
    let out = ArrayList<String>()
    out.add("Cron status")
    out.add("Enabled: ${if (cronEnabled) { "true" } else { "false" }}")
    out.add("Store: ${path.toString()}")
    out.add("Jobs: ${jobs.size}")
    out.add("Next wake: ${nextWakeAtMsText}")
    (String.join(out.toArray(), delimiter: "\n"), 0)
}

private func cronCmdStatusJson(path: Path): (String, Int64) {
    let jobs = cronLoadOrEmpty(path)
    var nextWakeAtMs: Int64 = 0
    for (j in jobs) {
        if (!j.enabled || j.state.nextRunAtMs <= 0) {
            continue
        }
        if (nextWakeAtMs <= 0 || j.state.nextRunAtMs < nextWakeAtMs) {
            nextWakeAtMs = j.state.nextRunAtMs
        }
    }
    let out = JsonObject()
    out.put("enabled", JsonBool(CliSettingManager.readGatewaySettings().enabled))
    out.put("storePath", JsonString(path.toString()))
    out.put("jobs", JsonInt(jobs.size))
    out.put("nextWakeAtMs", if (nextWakeAtMs > 0) { JsonInt(nextWakeAtMs) } else { JsonValue.fromStr("null") })
    (out.toJsonString(), 0)
}

private func cronJobToJson(j: CronJob): JsonObject {
    let schedule = JsonObject()
    schedule.put("kind", JsonString(j.schedule.kind))
    schedule.put("everyMs", JsonInt(j.schedule.everyMs))
    schedule.put("anchorMs", JsonInt(j.schedule.anchorMs))
    schedule.put("atMs", JsonInt(j.schedule.atMs))
    schedule.put("cronExpr", JsonString(j.schedule.cronExpr))
    schedule.put("timeZone", JsonString(j.schedule.timeZone))
    schedule.put("staggerMs", JsonInt(j.schedule.staggerMs))

    let state = JsonObject()
    state.put("nextRunAtMs", JsonInt(j.state.nextRunAtMs))
    state.put("lastRunAtMs", JsonInt(j.state.lastRunAtMs))
    state.put("lastError", JsonString(j.state.lastError))
    state.put("lastStatus", JsonString(j.state.lastStatus))
    state.put("consecutiveErrors", JsonInt(j.state.consecutiveErrors))
    state.put("runningAtMs", JsonInt(j.state.runningAtMs))
    state.put("scheduleErrorCount", JsonInt(j.state.scheduleErrorCount))
    state.put("lastFailureAlertAtMs", JsonInt(j.state.lastFailureAlertAtMs))

    let o = JsonObject()
    o.put("id", JsonString(j.id))
    o.put("createdAtMs", JsonInt(j.createdAtMs))
    o.put("name", JsonString(j.id))
    o.put("enabled", JsonBool(j.enabled))
    o.put("prompt", JsonString(j.prompt))
    o.put("sessionTarget", JsonString(j.sessionTarget))
    o.put("schedule", schedule)
    o.put("systemEvent", JsonString(j.systemEvent))
    o.put("wakeMode", JsonString(j.wakeMode))
    o.put("deliveryChannel", JsonString(j.deliveryChannel))
    o.put("deliveryTo", JsonString(j.deliveryTo))
    o.put("deliveryAnnounce", JsonBool(j.deliveryAnnounce))
    o.put("timeoutMs", JsonInt(j.timeoutMs))
    o.put("maxRetries", JsonInt(j.maxRetries))
    o.put("retryBackoffMs", JsonInt(j.retryBackoffMs))
    o.put("failureChannel", JsonString(j.failureChannel))
    o.put("failureTo", JsonString(j.failureTo))
    o.put("failureAnnounce", JsonBool(j.failureAnnounce))
    o.put("payloadKind", JsonString(j.payloadKind))
    o.put("deliveryMode", JsonString(j.deliveryMode))
    o.put("failureDestMode", JsonString(j.failureDestMode))
    o.put("deleteAfterRun", JsonBool(j.deleteAfterRun))
    o.put("updatedAtMs", JsonInt(j.updatedAtMs))
    o.put("description", JsonString(j.description))
    o.put("agentId", JsonString(j.agentId))
    o.put("sessionKey", JsonString(j.sessionKey))
    o.put("modelOverride", JsonString(j.modelOverride))
    o.put("thinkingLevel", JsonString(j.thinkingLevel))
    o.put("lightContext", JsonBool(j.lightContext))
    o.put("deliveryAccountId", JsonString(j.deliveryAccountId))
    o.put("bestEffortDeliver", JsonBool(j.bestEffortDeliver))
    o.put("failureAccountId", JsonString(j.failureAccountId))
    o.put("failureAlertAfter", JsonInt(j.failureAlertAfter))
    o.put("failureAlertCooldownMs", JsonInt(j.failureAlertCooldownMs))
    o.put("state", state)
    o
}

private func padRight(text: String, width: Int64): String {
    if (text.size >= width) {
        return text
    }
    var s = text
    var i = text.size
    while (i < width) {
        s = s + " "
        i += 1
    }
    s
}

private func ellipsis(text: String, width: Int64): String {
    if (text.size <= width) {
        return text
    }
    if (width <= 3) {
        return text[0..width]
    }
    text[0..width - 3] + "..."
}

private func formatScheduleSummary(j: CronJob): String {
    let k = j.schedule.kind.trimAscii().toAsciiLower()
    if (k == "every") {
        return "every ${j.schedule.everyMs}ms"
    }
    if (k == "at") {
        return "at ${j.schedule.atMs}"
    }
    if (k == "cron") {
        let tz = if (j.schedule.timeZone.trimAscii().isEmpty()) { "UTC" } else { j.schedule.timeZone.trimAscii() }
        return "cron ${j.schedule.cronExpr} (${tz})"
    }
    k
}

private func formatCronJobMutationForHuman(action: String, j: CronJob, path: Path): String {
    let lines = ArrayList<String>()
    lines.add("Cron job ${action}")
    lines.add("ID: ${j.id}")
    lines.add("Enabled: ${if (j.enabled) { "true" } else { "false" }}")
    lines.add("Schedule: ${formatScheduleSummary(j)}")
    lines.add("Session: ${j.sessionTarget}")
    if (!j.agentId.trimAscii().isEmpty()) {
        lines.add("Agent: ${j.agentId}")
    }
    if (!j.modelOverride.trimAscii().isEmpty()) {
        lines.add("Model: ${j.modelOverride}")
    }
    if (!j.deliveryChannel.trimAscii().isEmpty() || !j.deliveryTo.trimAscii().isEmpty()) {
        lines.add("Delivery: ${if (j.deliveryChannel.trimAscii().isEmpty()) { "default" } else { j.deliveryChannel }} -> ${if (j.deliveryTo.trimAscii().isEmpty()) { "(not set)" } else { j.deliveryTo }}")
    }
    if (j.state.nextRunAtMs > 0) {
        lines.add("Next run: ${j.state.nextRunAtMs}")
    }
    lines.add("Store: ${path.toString()}")
    lines.add("Prompt: ${ellipsis(j.prompt, 180)}")
    lines.add("Machine output: rerun with --json.")
    String.join(lines.toArray(), delimiter: "\n")
}

private func cronJobCommandOutput(action: String, j: CronJob, path: Path, json: Bool): (String, Int64) {
    if (json) {
        return (cronJobToJson(j).toJsonString(), 0)
    }
    (formatCronJobMutationForHuman(action, j, path), 0)
}

private func formatRelativeFuture(ms: Int64, nowMs: Int64): String {
    if (ms <= 0) { return "-" }
    let d = ms - nowMs
    if (d <= 0) { return "now" }
    let minute = 60 * 1000
    let hour = 60 * minute
    if (d < hour) {
        return "in ${max(1, d / minute)}m"
    }
    let h = d / hour
    return "in ${h}h"
}

private func formatRelativePast(ms: Int64, nowMs: Int64): String {
    if (ms <= 0) { return "-" }
    let d = nowMs - ms
    if (d <= 0) { return "just now" }
    let minute = 60 * 1000
    let hour = 60 * minute
    if (d < hour) {
        return "${max(1, d / minute)}m ago"
    }
    let h = d / hour
    return "${h}h ago"
}

private func cronCmdList(path: Path, sub: Array<String>): (String, Int64) {
    var includeDisabled = false
    var json = false
    var offset: Int64 = 0
    var limit: Int64 = 50
    var i: Int64 = 2
    while (i < sub.size) {
        let k = sub[i].trimAscii().toAsciiLower()
        if (k == "--json") {
            json = true
            i += 1
            continue
        }
        if (k == "--include-disabled" || k == "--all") {
            includeDisabled = true
            i += 1
            continue
        }
        if (k == "--offset" && i + 1 < sub.size) {
            try { offset = max(0, Int64.parse(sub[i + 1].trimAscii())) } catch (_: Exception) { () }
            i += 2
            continue
        }
        if (k == "--limit" && i + 1 < sub.size) {
            try { limit = max(1, Int64.parse(sub[i + 1].trimAscii())) } catch (_: Exception) { () }
            i += 2
            continue
        }
        i += 1
    }
    let all = ArrayList<CronJob>()
    for (j in cronLoadOrEmpty(path)) {
        if (includeDisabled || j.enabled) {
            all.add(j)
        }
    }
    let total = all.size
    if (json) {
        return cronCmdListJson(all.toArray(), offset, limit)
    }
    if (total == 0) {
        return ("No cron jobs.", 0)
    }
    let off = min(offset, total)
    let end = min(off + limit, total)
    let nowMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
    let lines = ArrayList<String>()
    lines.add(
        padRight("ID", 36) + " " +
            padRight("Name", 24) + " " +
            padRight("Schedule", 32) + " " +
            padRight("Next", 10) + " " +
            padRight("Last", 10) + " " +
            padRight("Status", 8) + " " +
            padRight("Target", 8) + " " +
            padRight("Agent ID", 10) + " " +
            "Model"
    )
    var idx = off
    while (idx < end) {
        let j = all[idx]
        let status = if (j.state.lastStatus.trimAscii().isEmpty()) {
            if (j.state.lastError.trimAscii().isEmpty()) { "ok" } else { "error" }
        } else {
            j.state.lastStatus
        }
        let target = j.sessionTarget.trimAscii().toAsciiLower()
        let targetShow = if (target == "isolated") { "isolated" } else { "main" }
        lines.add(
            padRight(ellipsis(j.id, 36), 36) + " " +
                padRight(ellipsis(j.id, 24), 24) + " " +
                padRight(ellipsis(formatScheduleSummary(j), 32), 32) + " " +
                padRight(formatRelativeFuture(j.state.nextRunAtMs, nowMs), 10) + " " +
                padRight(formatRelativePast(j.state.lastRunAtMs, nowMs), 10) + " " +
                padRight(ellipsis(status, 8), 8) + " " +
                padRight(ellipsis(targetShow, 8), 8) + " " +
                padRight("-", 10) + " " +
                "-"
        )
        idx += 1
    }
    (String.join(lines.toArray(), delimiter: "\n"), 0)
}

private func cronCmdListJson(all: Array<CronJob>, offset: Int64, limit: Int64): (String, Int64) {
    let total = all.size
    let off = min(max(0, offset), total)
    let lim = max(1, limit)
    let end = min(off + lim, total)
    let items = ArrayList<JsonValue>()
    var idx = off
    while (idx < end) {
        items.add(cronJobToJson(all[idx]))
        idx += 1
    }
    let out = JsonObject()
    out.put("jobs", JsonArray(items))
    out.put("total", JsonInt(total))
    out.put("offset", JsonInt(off))
    out.put("limit", JsonInt(lim))
    out.put("hasMore", JsonBool(end < total))
    out.put("nextOffset", if (end < total) { JsonInt(end) } else { JsonValue.fromStr("null") })
    (out.toJsonString(), 0)
}

private func joinFrom(parts: Array<String>, start: Int64): String {
    if (start >= parts.size) {
        return ""
    }
    var s = parts[start]
    var i = start + 1
    while (i < parts.size) {
        s = s + " " + parts[i]
        i += 1
    }
    s
}

/** 解析 `30s`/`5m`/`1h`/`2d` 或纯毫秒正整数（沿用当前 CLI 的直观写法）。 */
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

/** 仅 `20m`/`30s` 等带后缀的相对时间（用于 `--at`），避免把裸数字当成毫秒。 */
private func parseRelativeSuffixToMs(raw: String): Option<Int64> {
    let t = raw.trimAscii()
    if (t.size < 2) {
        return None<Int64>
    }
    let low = t.toAsciiLower()
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
 * `--at`：ISO8601、Unix 毫秒/秒级时间戳，或相对 `20m`（自此刻起）。
 */
private func parseAtToUnixMs(raw: String): Option<Int64> {
    let t = raw.trimAscii()
    if (t.isEmpty()) {
        return None<Int64>
    }
    try {
        let dt = DateTime.parse(t, "yyyy-MM-dd'T'HH:mm:ss'Z'")
        return Some(dt.toUnixTimeStamp().toMilliseconds())
    } catch (_: Exception) {
        ()
    }
    try {
        let dt2 = DateTime.parse(t, "yyyy-MM-dd'T'HH:mm:ss")
        return Some(dt2.toUnixTimeStamp().toMilliseconds())
    } catch (_: Exception) {
        ()
    }
    try {
        let dt3 = DateTime.parse(t, "yyyy-MM-dd HH:mm:ss")
        return Some(dt3.toUnixTimeStamp().toMilliseconds())
    } catch (_: Exception) {
        ()
    }
    try {
        let n = Int64.parse(t)
        if (n > 1_000_000_000_000) {
            return Some(n)
        }
        if (n > 1_000_000_000) {
            return Some(n * 1000)
        }
    } catch (_: Exception) {
        ()
    }
    match (parseRelativeSuffixToMs(t)) {
        case Some(dur) =>
            let now = DateTime.now().toUnixTimeStamp().toMilliseconds()
            Some(now + dur)
        case None => None<Int64>
    }
}

private func upsertJob(path: Path, job: CronJob): Unit {
    let list = ArrayList<CronJob>()
    for (j in cronLoadOrEmpty(path)) {
        if (j.id != job.id) {
            list.add(j)
        }
    }
    list.add(job)
    cronSave(path, list.toArray())
}

private func cronCmdAdd(path: Path, sub: Array<String>): (String, Int64) {
    if (sub.size < 3) {
        return cronErr("invalid cron.add params")
    }
    let tok = sub[2].trimAscii()
    let low = tok.toAsciiLower()
    if (tok.startsWith("--") || low == "-n") {
        return cronCmdAddNamed(path, sub)
    }
    return cronErr("invalid cron.add params")
}

/** 参考实现风格：`add --name X --every ... --session ... --message ...` */
private func cronCmdAddNamed(path: Path, sub: Array<String>): (String, Int64) {
    let json = cronArgvHasJsonFlag(sub, 2)
    var name = ""
    var everyOpt: Option<Int64> = None<Int64>
    var atOpt: Option<Int64> = None<Int64>
    var cronExprOpt: Option<String> = None<String>
    var tzStr = "UTC"
    var sessionTarget = "main"
    var message = ""
    var systemEvent = ""
    var wakeMode = ""
    var deliveryChannel = ""
    var deliveryTo = ""
    var announceFlag = false
    var timeoutMs: Int64 = 0
    var maxRetries: Int64 = 0
    var retryBackoffMs: Int64 = 1000
    var failureChannel = ""
    var failureTo = ""
    var failureAnnounce = true
    /** 仅与 `--cron` 同用；`--exact` 等价 stagger 0 */
    var staggerMsForCron: Int64 = 0
    var staggerFromFlag = false
    var staggerExact = false
    var description = ""
    var deleteAfterRun = false
    var agentId = ""
    var sessionKey = ""
    var modelOverride = ""
    var thinkingLevel = ""
    var lightContext = false
    var deliveryAccountId = ""
    var bestEffortDeliver = false
    var failureAccountId = ""
    var failureAlertAfter: Int64 = 0
    var failureAlertCooldownMs: Int64 = 0

    var i: Int64 = 2
    while (i < sub.size) {
        let key = sub[i].trimAscii()
        let k = key.toAsciiLower()
        if (k == "--json") {
            i += 1
            continue
        }
        if (k == "--message" || k == "-m") {
            message = joinFrom(sub, i + 1)
            break
        }
        if (k == "--name" || k == "-n") {
            if (i + 1 >= sub.size) {
                return cronErr("invalid cron.add params: missing --name value")
            }
            name = sub[i + 1].trimAscii()
            i += 2
            continue
        }
        if (k == "--every") {
            if (i + 1 >= sub.size) {
                return cronErr("invalid cron.add params: missing --every value")
            }
            match (parseDurationOrMs(sub[i + 1])) {
                case Some(ms) =>
                    if (ms <= 0) {
                        return cronErr("invalid cron.add params: --every must be positive")
                    }
                    everyOpt = Some(ms)
                case None => return cronErr("invalid cron.add params: invalid --every")
            }
            i += 2
            continue
        }
        if (k == "--at") {
            if (i + 1 >= sub.size) {
                return cronErr("invalid cron.add params: missing --at value")
            }
            match (parseAtToUnixMs(sub[i + 1])) {
                case Some(ms) =>
                    if (ms <= 0) {
                        return cronErr("invalid cron.add params: invalid --at")
                    }
                    atOpt = Some(ms)
                case None => return cronErr("invalid cron.add params: invalid --at")
            }
            i += 2
            continue
        }
        if (k == "--cron") {
            if (i + 1 >= sub.size) {
                return cronErr("invalid cron.add params: missing --cron value")
            }
            // 兼容 shell/聊天中的多 token 与引号：从 --cron 之后一路拼接到下一个以 -- 开头的参数
            var j = i + 1
            var sb = ""
            var firstPart = true
            while (j < sub.size) {
                let peek = sub[j].trimAscii()
                if (peek.startsWith("--")) {
                    break
                }
                if (!firstPart) {
                    sb = sb + " "
                }
                sb = sb + peek
                firstPart = false
                j += 1
            }
            let rawExpr = sb.trimAscii()
            if (rawExpr.isEmpty()) {
                return cronErr("invalid cron.add params: missing --cron value")
            }
            // 去掉整体首尾成对引号（"..." 或 '...')
            var cx = rawExpr
            if (cx.size >= 2) {
                let firstCh = cx[0..1]
                let lastCh = cx[cx.size - 1..cx.size]
                if ((firstCh == "\"" && lastCh == "\"") || (firstCh == "'" && lastCh == "'")) {
                    cx = cx[1..cx.size - 1].trimAscii()
                }
            }
            if (!isValidCronFiveExpression(cx)) {
                return cronErr("invalid cron.add params: invalid --cron")
            }
            cronExprOpt = Some(cx)
            i = j
            continue
        }
        if (k == "--tz") {
            if (i + 1 >= sub.size) {
                return cronErr("invalid cron.add params: missing --tz value")
            }
            let rawTz = sub[i + 1].trimAscii()
            if (cronResolveTimeZoneOffsetMinutes(rawTz).isNone()) {
                return cronErr("invalid cron.add params: invalid --tz (use UTC±、UTC+8 或常见 IANA 如 Asia/Shanghai)")
            }
            tzStr = rawTz
            i += 2
            continue
        }
        if (k == "--system-event") {
            if (i + 1 >= sub.size) {
                return ("--system-event 缺少值。", 1)
            }
            systemEvent = sub[i + 1].trimAscii()
            i += 2
            continue
        }
        if (k == "--wake-mode" || k == "--wake") {
            if (i + 1 >= sub.size) {
                return ("--wake / --wake-mode 缺少值。", 1)
            }
            wakeMode = sub[i + 1].trimAscii()
            i += 2
            continue
        }
        if (k == "--channel") {
            if (i + 1 >= sub.size) {
                return ("--channel 缺少值（如 feishu、qq）。", 1)
            }
            deliveryChannel = sub[i + 1].trimAscii()
            i += 2
            continue
        }
        if (k == "--to") {
            if (i + 1 >= sub.size) {
                return ("--to 缺少 peer/chat 标识。", 1)
            }
            deliveryTo = sub[i + 1].trimAscii()
            i += 2
            continue
        }
        if (k == "--announce") {
            announceFlag = true
            i += 1
            continue
        }
        if (k == "--session") {
            if (i + 1 >= sub.size) {
                return ("--session 缺少值（main|isolated|current|session:...）。", 1)
            }
            sessionTarget = sub[i + 1].trimAscii()
            i += 2
            continue
        }
        if (k == "--timeout-ms") {
            if (i + 1 >= sub.size) { return ("--timeout-ms 缺少值。", 1) }
            try { timeoutMs = Int64.parse(sub[i + 1].trimAscii()) } catch (_: Exception) { return ("--timeout-ms 需为整数。", 1) }
            i += 2
            continue
        }
        if (k == "--timeout-seconds") {
            if (i + 1 >= sub.size) { return ("--timeout-seconds 缺少值。", 1) }
            try {
                let sec = Int64.parse(sub[i + 1].trimAscii())
                if (sec > 0) {
                    timeoutMs = sec * 1000
                }
            } catch (_: Exception) {
                return ("--timeout-seconds 需为正整数。", 1)
            }
            i += 2
            continue
        }
        if (k == "--exact") {
            staggerExact = true
            i += 1
            continue
        }
        if (k == "--stagger") {
            if (i + 1 >= sub.size) {
                return cronErr("invalid cron.add params: missing --stagger value")
            }
            match (parseDurationOrMs(sub[i + 1])) {
                case Some(ms) =>
                    if (ms <= 0) {
                        return cronErr("invalid cron.add params: --stagger must be positive")
                    }
                    staggerMsForCron = ms
                    staggerFromFlag = true
                case None => return cronErr("invalid cron.add params: invalid --stagger (e.g. 30s, 5m)")
            }
            i += 2
            continue
        }
        if (k == "--max-retries") {
            if (i + 1 >= sub.size) { return ("--max-retries 缺少值。", 1) }
            try { maxRetries = max(0, Int64.parse(sub[i + 1].trimAscii())) } catch (_: Exception) { return ("--max-retries 需为整数。", 1) }
            i += 2
            continue
        }
        if (k == "--retry-backoff-ms") {
            if (i + 1 >= sub.size) { return ("--retry-backoff-ms 缺少值。", 1) }
            try { retryBackoffMs = max(1, Int64.parse(sub[i + 1].trimAscii())) } catch (_: Exception) { return ("--retry-backoff-ms 需为整数。", 1) }
            i += 2
            continue
        }
        if (k == "--failure-channel") {
            if (i + 1 >= sub.size) { return ("--failure-channel 缺少值。", 1) }
            failureChannel = sub[i + 1].trimAscii()
            i += 2
            continue
        }
        if (k == "--failure-to") {
            if (i + 1 >= sub.size) { return ("--failure-to 缺少值。", 1) }
            failureTo = sub[i + 1].trimAscii()
            i += 2
            continue
        }
        if (k == "--failure-announce") {
            failureAnnounce = true
            i += 1
            continue
        }
        if (k == "--no-failure-announce") {
            failureAnnounce = false
            i += 1
            continue
        }
        if (k == "--description") {
            if (i + 1 >= sub.size) {
                return cronErr("invalid cron.add params: missing --description value")
            }
            description = sub[i + 1].trimAscii()
            i += 2
            continue
        }
        if (k == "--delete-after-run") {
            deleteAfterRun = true
            i += 1
            continue
        }
        if (k == "--no-delete-after-run") {
            deleteAfterRun = false
            i += 1
            continue
        }
        if (k == "--agent" || k == "--agent-id") {
            if (i + 1 >= sub.size) {
                return cronErr("invalid cron.add params: missing --agent value")
            }
            agentId = sub[i + 1].trimAscii()
            i += 2
            continue
        }
        if (k == "--session-key") {
            if (i + 1 >= sub.size) {
                return cronErr("invalid cron.add params: missing --session-key value")
            }
            sessionKey = sub[i + 1].trimAscii()
            i += 2
            continue
        }
        if (k == "--model" || k == "--model-override") {
            if (i + 1 >= sub.size) {
                return cronErr("invalid cron.add params: missing --model value")
            }
            modelOverride = sub[i + 1].trimAscii()
            i += 2
            continue
        }
        if (k == "--thinking-level") {
            if (i + 1 >= sub.size) {
                return cronErr("invalid cron.add params: missing --thinking-level value")
            }
            thinkingLevel = sub[i + 1].trimAscii()
            i += 2
            continue
        }
        if (k == "--light-context") {
            lightContext = true
            i += 1
            continue
        }
        if (k == "--no-light-context") {
            lightContext = false
            i += 1
            continue
        }
        if (k == "--delivery-account-id") {
            if (i + 1 >= sub.size) {
                return cronErr("invalid cron.add params: missing --delivery-account-id value")
            }
            deliveryAccountId = sub[i + 1].trimAscii()
            i += 2
            continue
        }
        if (k == "--best-effort-deliver") {
            bestEffortDeliver = true
            i += 1
            continue
        }
        if (k == "--failure-account-id") {
            if (i + 1 >= sub.size) {
                return cronErr("invalid cron.add params: missing --failure-account-id value")
            }
            failureAccountId = sub[i + 1].trimAscii()
            i += 2
            continue
        }
        if (k == "--failure-alert-after") {
            if (i + 1 >= sub.size) {
                return cronErr("invalid cron.add params: missing --failure-alert-after value")
            }
            try {
                failureAlertAfter = max(0, Int64.parse(sub[i + 1].trimAscii()))
            } catch (_: Exception) {
                return cronErr("invalid cron.add params: --failure-alert-after must be integer")
            }
            i += 2
            continue
        }
        if (k == "--failure-alert-cooldown-ms") {
            if (i + 1 >= sub.size) {
                return cronErr("invalid cron.add params: missing --failure-alert-cooldown-ms value")
            }
            try {
                failureAlertCooldownMs = max(0, Int64.parse(sub[i + 1].trimAscii()))
            } catch (_: Exception) {
                return cronErr("invalid cron.add params: --failure-alert-cooldown-ms must be integer")
            }
            i += 2
            continue
        }
        return cronErr("invalid cron.add params: unknown option")
    }

    if (name.isEmpty()) {
        return cronErr("invalid cron.add params: missing --name")
    }
    if (message.isEmpty()) {
        return cronErr("invalid cron.add params: missing --message")
    }
    let hasEvery = everyOpt.isSome()
    let hasAt = atOpt.isSome()
    let hasCron = cronExprOpt.isSome()
    let modeCount = (if (hasEvery) {
        1
    } else {
        0
    }) + (if (hasAt) {
        1
    } else {
        0
    }) + (if (hasCron) {
        1
    } else {
        0
    })
    if (modeCount != 1) {
        return cronErr("invalid cron.add params: choose exactly one schedule")
    }
    if (staggerExact && staggerFromFlag) {
        return cronErr("invalid cron.add params: choose either --stagger or --exact, not both")
    }
    if ((staggerExact || staggerFromFlag) && !hasCron) {
        return cronErr("invalid cron.add params: --stagger/--exact are only valid with --cron")
    }
    let staggerFinal = if (hasCron) {
        if (staggerExact) {
            0
        } else if (staggerFromFlag) {
            staggerMsForCron
        } else {
            0
        }
    } else {
        0
    }

    let createdMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
    if (let Some(ev) <- everyOpt) {
        // 使用主构造函数，避免部分仓颉版本在超长函数内对 `CronSchedule.every` 静态方法解析异常
        let scheduleEvery = CronSchedule("every", ev, 0, 0, "", "", 0)
        let jobEvery = CronJob(
            name,
            message,
            scheduleEvery,
            createdAtMs: createdMs,
            sessionTarget: sessionTarget,
            state: CronJobState(),
            systemEvent: systemEvent,
            wakeMode: wakeMode,
            deliveryChannel: deliveryChannel,
            deliveryTo: deliveryTo,
            deliveryAnnounce: announceFlag,
            timeoutMs: timeoutMs,
            maxRetries: maxRetries,
            retryBackoffMs: retryBackoffMs,
            failureChannel: failureChannel,
            failureTo: failureTo,
            failureAnnounce: failureAnnounce,
            payloadKind: "agentTurn",
            deliveryMode: "",
            failureDestMode: "",
            deleteAfterRun: deleteAfterRun,
            updatedAtMs: createdMs,
            description: description,
            agentId: agentId,
            sessionKey: sessionKey,
            modelOverride: modelOverride,
            thinkingLevel: thinkingLevel,
            lightContext: lightContext,
            deliveryAccountId: deliveryAccountId,
            bestEffortDeliver: bestEffortDeliver,
            failureAccountId: failureAccountId,
            failureAlertAfter: failureAlertAfter,
            failureAlertCooldownMs: failureAlertCooldownMs
        )
        upsertJob(path, jobEvery)
        return cronJobCommandOutput("created", jobEvery, path, json)
    }
    if (let Some(atv) <- atOpt) {
        let scheduleAt = CronSchedule("at", 0, 0, atv, "", "", 0)
        let jobAt = CronJob(
            name,
            message,
            scheduleAt,
            createdAtMs: createdMs,
            sessionTarget: sessionTarget,
            state: CronJobState(),
            systemEvent: systemEvent,
            wakeMode: wakeMode,
            deliveryChannel: deliveryChannel,
            deliveryTo: deliveryTo,
            deliveryAnnounce: announceFlag,
            timeoutMs: timeoutMs,
            maxRetries: maxRetries,
            retryBackoffMs: retryBackoffMs,
            failureChannel: failureChannel,
            failureTo: failureTo,
            failureAnnounce: failureAnnounce,
            payloadKind: "agentTurn",
            deliveryMode: "",
            failureDestMode: "",
            deleteAfterRun: deleteAfterRun,
            updatedAtMs: createdMs,
            description: description,
            agentId: agentId,
            sessionKey: sessionKey,
            modelOverride: modelOverride,
            thinkingLevel: thinkingLevel,
            lightContext: lightContext,
            deliveryAccountId: deliveryAccountId,
            bestEffortDeliver: bestEffortDeliver,
            failureAccountId: failureAccountId,
            failureAlertAfter: failureAlertAfter,
            failureAlertCooldownMs: failureAlertCooldownMs
        )
        upsertJob(path, jobAt)
        return cronJobCommandOutput("created", jobAt, path, json)
    }
    if (let Some(cronEx) <- cronExprOpt) {
        let scheduleCron = CronSchedule("cron", 0, 0, 0, cronEx.trimAscii(), tzStr.trimAscii(), staggerFinal)
        let jobCron = CronJob(
            name,
            message,
            scheduleCron,
            createdAtMs: createdMs,
            sessionTarget: sessionTarget,
            state: CronJobState(),
            systemEvent: systemEvent,
            wakeMode: wakeMode,
            deliveryChannel: deliveryChannel,
            deliveryTo: deliveryTo,
            deliveryAnnounce: announceFlag,
            timeoutMs: timeoutMs,
            maxRetries: maxRetries,
            retryBackoffMs: retryBackoffMs,
            failureChannel: failureChannel,
            failureTo: failureTo,
            failureAnnounce: failureAnnounce,
            payloadKind: "agentTurn",
            deliveryMode: "",
            failureDestMode: "",
            deleteAfterRun: deleteAfterRun,
            updatedAtMs: createdMs,
            description: description,
            agentId: agentId,
            sessionKey: sessionKey,
            modelOverride: modelOverride,
            thinkingLevel: thinkingLevel,
            lightContext: lightContext,
            deliveryAccountId: deliveryAccountId,
            bestEffortDeliver: bestEffortDeliver,
            failureAccountId: failureAccountId,
            failureAlertAfter: failureAlertAfter,
            failureAlertCooldownMs: failureAlertCooldownMs
        )
        upsertJob(path, jobCron)
        return cronJobCommandOutput("created", jobCron, path, json)
    }
    return cronErr("cron.add failed")
}

private func cronCmdAddLegacy(path: Path, sub: Array<String>): (String, Int64) {
    if (sub.size < 3) {
        return ("用法: gateway cron add every <id> <everyMs> <prompt...>", 1)
    }
    let mode = sub[2].trimAscii().toAsciiLower()
    if (mode == "every") {
        if (sub.size < 6) {
            return ("用法: gateway cron add every <id> <everyMs> <prompt...>", 1)
        }
        let id = sub[3].trimAscii()
        if (id.isEmpty()) {
            return ("id 不能为空。", 1)
        }
        let msStr = sub[4].trimAscii()
        var everyMs: Int64 = 0
        try {
            everyMs = Int64.parse(msStr)
        } catch (_: Exception) {
            return ("everyMs 不是合法整数: ${msStr}", 1)
        }
        if (everyMs <= 0) {
            return ("everyMs 须为正整数。", 1)
        }
        let prompt = joinFrom(sub, 5)
        if (prompt.isEmpty()) {
            return ("prompt 不能为空。", 1)
        }
        let job = CronJob(
            id,
            prompt,
            CronSchedule.every(everyMs),
            createdAtMs: DateTime.now().toUnixTimeStamp().toMilliseconds(),
            state: CronJobState()
        )
        upsertJob(path, job)
        return (
            "已添加/更新 every 任务 id=${id}，everyMs=${everyMs}。若 gateway serve 在跑，将按间隔触发。\n→ ${path.toString()}",
            0
        )
    }
    if (mode == "at") {
        if (sub.size < 6) {
            return ("用法: gateway cron add at <id> <atMs> <prompt...>", 1)
        }
        let id = sub[3].trimAscii()
        if (id.isEmpty()) {
            return ("id 不能为空。", 1)
        }
        let atStr = sub[4].trimAscii()
        match (parseAtToUnixMs(atStr)) {
            case Some(atMs) =>
                if (atMs <= 0) {
                    return ("at 时间无效: ${atStr}", 1)
                }
                let prompt = joinFrom(sub, 5)
                if (prompt.isEmpty()) {
                    return ("prompt 不能为空。", 1)
                }
                let job = CronJob(
                    id,
                    prompt,
                    CronSchedule.at(atMs),
                    createdAtMs: DateTime.now().toUnixTimeStamp().toMilliseconds(),
                    state: CronJobState()
                )
                upsertJob(path, job)
                return ("已添加/更新 at 任务 id=${id}，atMs=${atMs}（一次性）。\n→ ${path.toString()}", 0)
            case None => return ("无法解析 at 时间: ${atStr}", 1)
        }
    }
    return ("add 的第三段须为 every 或 at。", 1)
}

private func cronCmdEdit(path: Path, sub: Array<String>): (String, Int64) {
    if (sub.size < 4) {
        return ("用法: gateway cron edit <jobId> --enabled true|false\n或: gateway cron edit <jobId> --message <新提示...>", 1)
    }
    let jobId = sub[2].trimAscii()
    if (jobId.isEmpty()) {
        return ("jobId 不能为空。", 1)
    }
    var enabledOpt: Option<Bool> = None<Bool>
    var messageOpt: Option<String> = None<String>

    var i: Int64 = 3
    while (i < sub.size) {
        let key = sub[i].trimAscii().toAsciiLower()
        if (key == "--message" || key == "-m") {
            messageOpt = Some(joinFrom(sub, i + 1))
            break
        }
        if (key == "--enabled") {
            if (i + 1 >= sub.size) {
                return ("--enabled 缺少 true|false。", 1)
            }
            let v = sub[i + 1].trimAscii().toAsciiLower()
            if (v == "true" || v == "1" || v == "yes") {
                enabledOpt = Some(true)
            } else if (v == "false" || v == "0" || v == "no") {
                enabledOpt = Some(false)
            } else {
                return ("--enabled 须为 true 或 false。", 1)
            }
            i += 2
            continue
        }
        return ("未知参数: ${sub[i]}", 1)
    }

    if (enabledOpt.isNone() && messageOpt.isNone()) {
        return ("请指定 --enabled 或 --message。", 1)
    }

    let list = ArrayList<CronJob>()
    var found = false
    for (j in cronLoadOrEmpty(path)) {
        if (j.id == jobId) {
            found = true
            if (let Some(en) <- enabledOpt) {
                j.enabled = en
            }
            if (let Some(msg) <- messageOpt) {
                if (!msg.isEmpty()) {
                    j.prompt = msg
                }
            }
        }
        list.add(j)
    }
    if (!found) {
        return ("未找到 jobId=${jobId}。", 1)
    }
    cronSave(path, list.toArray())
    return ("已更新 jobId=${jobId}。\n→ ${path.toString()}", 0)
}

private func parseJobIdFlag(sub: Array<String>, start: Int64): Option<String> {
    var i = start
    while (i < sub.size) {
        let k = sub[i].trimAscii().toAsciiLower()
        if (k == "--job-id" || k == "--id") {
            if (i + 1 >= sub.size) {
                return None<String>
            }
            let v = sub[i + 1].trimAscii()
            if (v.isEmpty()) {
                return None<String>
            }
            return Some(v)
        }
        i += 1
    }
    None<String>
}

private func cronCmdUpdate(path: Path, sub: Array<String>): (String, Int64) {
    if (sub.size < 4) {
        return cronErr("invalid cron.update params")
    }
    match (parseJobIdFlag(sub, 2)) {
        case Some(jobId) =>
            let json = cronArgvHasJsonFlag(sub, 2)
            var enabledOpt: Option<Bool> = None<Bool>
            var messageOpt: Option<String> = None<String>
            var sessionOpt: Option<String> = None<String>
            var everyOpt: Option<Int64> = None<Int64>
            var atOpt: Option<Int64> = None<Int64>
            var cronExprOpt: Option<String> = None<String>
            var tzOpt: Option<String> = None<String>
            var systemEventOpt: Option<String> = None<String>
            var wakeModeOpt: Option<String> = None<String>
            var channelOpt: Option<String> = None<String>
            var toOpt: Option<String> = None<String>
            var timeoutMsOpt: Option<Int64> = None<Int64>
            var maxRetriesOpt: Option<Int64> = None<Int64>
            var retryBackoffOpt: Option<Int64> = None<Int64>
            var failureChannelOpt: Option<String> = None<String>
            var failureToOpt: Option<String> = None<String>
            var announceSet = false
            var announceValue = false
            var failureAnnounceSet = false
            var failureAnnounceValue = true
            var staggerMsPatch: Option<Int64> = None<Int64>
            var staggerExactPatch = false
            var descriptionOpt: Option<String> = None<String>
            var deleteAfterRunOpt: Option<Bool> = None<Bool>
            var agentIdOpt: Option<String> = None<String>
            var sessionKeyOpt: Option<String> = None<String>
            var modelOverrideOpt: Option<String> = None<String>
            var thinkingLevelOpt: Option<String> = None<String>
            var lightContextOpt: Option<Bool> = None<Bool>
            var deliveryAccountIdOpt: Option<String> = None<String>
            var bestEffortDeliverOpt: Option<Bool> = None<Bool>
            var failureAccountIdOpt: Option<String> = None<String>
            var failureAlertAfterOpt: Option<Int64> = None<Int64>
            var failureAlertCooldownOpt: Option<Int64> = None<Int64>
            var i: Int64 = 2
            var touched = false
            while (i < sub.size) {
                let k = sub[i].trimAscii().toAsciiLower()
                if (k == "--json") {
                    i += 1
                    continue
                }
                if (k == "--job-id" || k == "--id") {
                    i += 2
                    continue
                }
                if (k == "--enabled") {
                    if (i + 1 >= sub.size) {
                        return cronErr("invalid cron.update params: missing --enabled value")
                    }
                    let v = sub[i + 1].trimAscii().toAsciiLower()
                    if (v == "true" || v == "1" || v == "yes" || v == "on") {
                        enabledOpt = Some(true)
                    } else if (v == "false" || v == "0" || v == "no" || v == "off") {
                        enabledOpt = Some(false)
                    } else {
                        return cronErr("invalid cron.update params: invalid --enabled")
                    }
                    touched = true
                    i += 2
                    continue
                }
                if (k == "--message" || k == "-m") {
                    messageOpt = Some(joinFrom(sub, i + 1))
                    touched = true
                    break
                }
                if (k == "--session") {
                    if (i + 1 >= sub.size) {
                        return ("--session 缺少值。", 1)
                    }
                    sessionOpt = Some(sub[i + 1].trimAscii())
                    touched = true
                    i += 2
                    continue
                }
                if (k == "--every") {
                    if (i + 1 >= sub.size) {
                        return ("--every 缺少值。", 1)
                    }
                    match (parseDurationOrMs(sub[i + 1])) {
                        case Some(ms) =>
                            if (ms <= 0) {
                                return ("--every 须为正数。", 1)
                            }
                            everyOpt = Some(ms)
                        case None => return ("无法解析 --every: ${sub[i + 1]}", 1)
                    }
                    touched = true
                    i += 2
                    continue
                }
                if (k == "--at") {
                    if (i + 1 >= sub.size) {
                        return ("--at 缺少值。", 1)
                    }
                    match (parseAtToUnixMs(sub[i + 1])) {
                        case Some(ms) =>
                            if (ms <= 0) {
                                return ("--at 时间无效。", 1)
                            }
                            atOpt = Some(ms)
                        case None => return ("无法解析 --at: ${sub[i + 1]}", 1)
                    }
                    touched = true
                    i += 2
                    continue
                }
                if (k == "--cron") {
                    if (i + 1 >= sub.size) {
                        return ("--cron 缺少表达式。", 1)
                    }
                    let cx = sub[i + 1].trimAscii()
                    if (!isValidCronFiveExpression(cx)) {
                        return ("--cron 非法: ${cx}", 1)
                    }
                    cronExprOpt = Some(cx)
                    touched = true
                    i += 2
                    continue
                }
                if (k == "--tz") {
                    if (i + 1 >= sub.size) {
                        return ("--tz 缺少值。", 1)
                    }
                    let tzRaw = sub[i + 1].trimAscii()
                    if (cronResolveTimeZoneOffsetMinutes(tzRaw).isNone()) {
                        return ("无法解析 --tz: ${tzRaw}（可用 UTC±、UTC+8 或 Asia/Shanghai 等）", 1)
                    }
                    tzOpt = Some(tzRaw)
                    touched = true
                    i += 2
                    continue
                }
                if (k == "--system-event") {
                    if (i + 1 >= sub.size) {
                        return ("--system-event 缺少值。", 1)
                    }
                    systemEventOpt = Some(sub[i + 1].trimAscii())
                    touched = true
                    i += 2
                    continue
                }
                if (k == "--wake-mode" || k == "--wake") {
                    if (i + 1 >= sub.size) {
                        return ("--wake / --wake-mode 缺少值。", 1)
                    }
                    wakeModeOpt = Some(sub[i + 1].trimAscii())
                    touched = true
                    i += 2
                    continue
                }
                if (k == "--channel") {
                    if (i + 1 >= sub.size) {
                        return ("--channel 缺少值。", 1)
                    }
                    channelOpt = Some(sub[i + 1].trimAscii())
                    touched = true
                    i += 2
                    continue
                }
                if (k == "--to") {
                    if (i + 1 >= sub.size) {
                        return ("--to 缺少值。", 1)
                    }
                    toOpt = Some(sub[i + 1].trimAscii())
                    touched = true
                    i += 2
                    continue
                }
                if (k == "--timeout-ms") {
                    if (i + 1 >= sub.size) { return ("--timeout-ms 缺少值。", 1) }
                    try { timeoutMsOpt = Some(Int64.parse(sub[i + 1].trimAscii())) } catch (_: Exception) { return ("--timeout-ms 需为整数。", 1) }
                    touched = true
                    i += 2
                    continue
                }
                if (k == "--timeout-seconds") {
                    if (i + 1 >= sub.size) { return ("--timeout-seconds 缺少值。", 1) }
                    try {
                        let sec = Int64.parse(sub[i + 1].trimAscii())
                        if (sec > 0) {
                            timeoutMsOpt = Some(sec * 1000)
                        }
                    } catch (_: Exception) {
                        return ("--timeout-seconds 需为正整数。", 1)
                    }
                    touched = true
                    i += 2
                    continue
                }
                if (k == "--exact") {
                    staggerExactPatch = true
                    touched = true
                    i += 1
                    continue
                }
                if (k == "--stagger") {
                    if (i + 1 >= sub.size) {
                        return cronErr("invalid cron.update params: missing --stagger value")
                    }
                    match (parseDurationOrMs(sub[i + 1])) {
                        case Some(ms) =>
                            if (ms <= 0) {
                                return cronErr("invalid cron.update params: --stagger must be positive")
                            }
                            staggerMsPatch = Some(ms)
                        case None => return cronErr("invalid cron.update params: invalid --stagger")
                    }
                    touched = true
                    i += 2
                    continue
                }
                if (k == "--max-retries") {
                    if (i + 1 >= sub.size) { return ("--max-retries 缺少值。", 1) }
                    try { maxRetriesOpt = Some(max(0, Int64.parse(sub[i + 1].trimAscii()))) } catch (_: Exception) { return ("--max-retries 需为整数。", 1) }
                    touched = true
                    i += 2
                    continue
                }
                if (k == "--retry-backoff-ms") {
                    if (i + 1 >= sub.size) { return ("--retry-backoff-ms 缺少值。", 1) }
                    try { retryBackoffOpt = Some(max(1, Int64.parse(sub[i + 1].trimAscii()))) } catch (_: Exception) { return ("--retry-backoff-ms 需为整数。", 1) }
                    touched = true
                    i += 2
                    continue
                }
                if (k == "--failure-channel") {
                    if (i + 1 >= sub.size) { return ("--failure-channel 缺少值。", 1) }
                    failureChannelOpt = Some(sub[i + 1].trimAscii())
                    touched = true
                    i += 2
                    continue
                }
                if (k == "--failure-to") {
                    if (i + 1 >= sub.size) { return ("--failure-to 缺少值。", 1) }
                    failureToOpt = Some(sub[i + 1].trimAscii())
                    touched = true
                    i += 2
                    continue
                }
                if (k == "--announce") {
                    announceSet = true
                    announceValue = true
                    touched = true
                    i += 1
                    continue
                }
                if (k == "--no-announce") {
                    announceSet = true
                    announceValue = false
                    touched = true
                    i += 1
                    continue
                }
                if (k == "--failure-announce") {
                    failureAnnounceSet = true
                    failureAnnounceValue = true
                    touched = true
                    i += 1
                    continue
                }
                if (k == "--no-failure-announce") {
                    failureAnnounceSet = true
                    failureAnnounceValue = false
                    touched = true
                    i += 1
                    continue
                }
                if (k == "--description") {
                    if (i + 1 >= sub.size) {
                        return cronErr("invalid cron.update params: missing --description value")
                    }
                    descriptionOpt = Some(sub[i + 1].trimAscii())
                    touched = true
                    i += 2
                    continue
                }
                if (k == "--delete-after-run") {
                    deleteAfterRunOpt = Some(true)
                    touched = true
                    i += 1
                    continue
                }
                if (k == "--no-delete-after-run") {
                    deleteAfterRunOpt = Some(false)
                    touched = true
                    i += 1
                    continue
                }
                if (k == "--agent" || k == "--agent-id") {
                    if (i + 1 >= sub.size) {
                        return cronErr("invalid cron.update params: missing --agent value")
                    }
                    agentIdOpt = Some(sub[i + 1].trimAscii())
                    touched = true
                    i += 2
                    continue
                }
                if (k == "--session-key") {
                    if (i + 1 >= sub.size) {
                        return cronErr("invalid cron.update params: missing --session-key value")
                    }
                    sessionKeyOpt = Some(sub[i + 1].trimAscii())
                    touched = true
                    i += 2
                    continue
                }
                if (k == "--model" || k == "--model-override") {
                    if (i + 1 >= sub.size) {
                        return cronErr("invalid cron.update params: missing --model value")
                    }
                    modelOverrideOpt = Some(sub[i + 1].trimAscii())
                    touched = true
                    i += 2
                    continue
                }
                if (k == "--thinking-level") {
                    if (i + 1 >= sub.size) {
                        return cronErr("invalid cron.update params: missing --thinking-level value")
                    }
                    thinkingLevelOpt = Some(sub[i + 1].trimAscii())
                    touched = true
                    i += 2
                    continue
                }
                if (k == "--light-context") {
                    lightContextOpt = Some(true)
                    touched = true
                    i += 1
                    continue
                }
                if (k == "--no-light-context") {
                    lightContextOpt = Some(false)
                    touched = true
                    i += 1
                    continue
                }
                if (k == "--delivery-account-id") {
                    if (i + 1 >= sub.size) {
                        return cronErr("invalid cron.update params: missing --delivery-account-id value")
                    }
                    deliveryAccountIdOpt = Some(sub[i + 1].trimAscii())
                    touched = true
                    i += 2
                    continue
                }
                if (k == "--best-effort-deliver") {
                    bestEffortDeliverOpt = Some(true)
                    touched = true
                    i += 1
                    continue
                }
                if (k == "--no-best-effort-deliver") {
                    bestEffortDeliverOpt = Some(false)
                    touched = true
                    i += 1
                    continue
                }
                if (k == "--failure-account-id") {
                    if (i + 1 >= sub.size) {
                        return cronErr("invalid cron.update params: missing --failure-account-id value")
                    }
                    failureAccountIdOpt = Some(sub[i + 1].trimAscii())
                    touched = true
                    i += 2
                    continue
                }
                if (k == "--failure-alert-after") {
                    if (i + 1 >= sub.size) {
                        return cronErr("invalid cron.update params: missing --failure-alert-after value")
                    }
                    try {
                        failureAlertAfterOpt = Some(max(0, Int64.parse(sub[i + 1].trimAscii())))
                    } catch (_: Exception) {
                        return cronErr("invalid cron.update params: --failure-alert-after must be integer")
                    }
                    touched = true
                    i += 2
                    continue
                }
                if (k == "--failure-alert-cooldown-ms") {
                    if (i + 1 >= sub.size) {
                        return cronErr("invalid cron.update params: missing --failure-alert-cooldown-ms value")
                    }
                    try {
                        failureAlertCooldownOpt = Some(max(0, Int64.parse(sub[i + 1].trimAscii())))
                    } catch (_: Exception) {
                        return cronErr("invalid cron.update params: --failure-alert-cooldown-ms must be integer")
                    }
                    touched = true
                    i += 2
                    continue
                }
                return cronErr("invalid cron.update params: unknown option")
            }
            if (!touched) {
                return cronErr("invalid cron.update params: empty patch")
            }
            if (staggerExactPatch && staggerMsPatch.isSome()) {
                return cronErr("invalid cron.update params: choose either --stagger or --exact, not both")
            }
            if ((staggerExactPatch || staggerMsPatch.isSome()) && (everyOpt.isSome() || atOpt.isSome())) {
                return cronErr("invalid cron.update params: --stagger/--exact are not valid with --every/--at")
            }
            let list = ArrayList<CronJob>()
            var found = false
            var updatedJob: Option<CronJob> = None<CronJob>
            for (j in cronLoadOrEmpty(path)) {
                if (j.id == jobId) {
                    found = true
                    let nowMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
                    if (let Some(v) <- enabledOpt) { j.enabled = v }
                    if (let Some(v) <- messageOpt) {
                        if (!v.trimAscii().isEmpty()) {
                            j.prompt = v
                        }
                    }
                    if (let Some(v) <- sessionOpt) { j.sessionTarget = v }
                    if (let Some(v) <- systemEventOpt) { j.systemEvent = v }
                    if (let Some(v) <- wakeModeOpt) { j.wakeMode = v }
                    if (let Some(v) <- channelOpt) { j.deliveryChannel = v }
                    if (let Some(v) <- toOpt) { j.deliveryTo = v }
                    if (announceSet) { j.deliveryAnnounce = announceValue }
                    if (let Some(v) <- timeoutMsOpt) { j.timeoutMs = v }
                    if (let Some(v) <- maxRetriesOpt) { j.maxRetries = v }
                    if (let Some(v) <- retryBackoffOpt) { j.retryBackoffMs = v }
                    if (let Some(v) <- failureChannelOpt) { j.failureChannel = v }
                    if (let Some(v) <- failureToOpt) { j.failureTo = v }
                    if (failureAnnounceSet) { j.failureAnnounce = failureAnnounceValue }
                    if (let Some(v) <- descriptionOpt) { j.description = v }
                    if (let Some(v) <- deleteAfterRunOpt) { j.deleteAfterRun = v }
                    if (let Some(v) <- agentIdOpt) { j.agentId = v }
                    if (let Some(v) <- sessionKeyOpt) { j.sessionKey = v }
                    if (let Some(v) <- modelOverrideOpt) { j.modelOverride = v }
                    if (let Some(v) <- thinkingLevelOpt) { j.thinkingLevel = v }
                    if (let Some(v) <- lightContextOpt) { j.lightContext = v }
                    if (let Some(v) <- deliveryAccountIdOpt) { j.deliveryAccountId = v }
                    if (let Some(v) <- bestEffortDeliverOpt) { j.bestEffortDeliver = v }
                    if (let Some(v) <- failureAccountIdOpt) { j.failureAccountId = v }
                    if (let Some(v) <- failureAlertAfterOpt) { j.failureAlertAfter = v }
                    if (let Some(v) <- failureAlertCooldownOpt) { j.failureAlertCooldownMs = v }
                    j.updatedAtMs = nowMs

                    let hasEvery = everyOpt.isSome()
                    let hasAt = atOpt.isSome()
                    let hasCron = cronExprOpt.isSome()
                    let modeCount = (if (hasEvery) { 1 } else { 0 }) + (if (hasAt) { 1 } else { 0 }) + (if (hasCron) { 1 } else { 0 })
                    if (modeCount > 1) {
                        return cronErr("invalid cron.update params: choose at most one schedule")
                    }
                    if (let Some(v) <- everyOpt) {
                        j.schedule = CronSchedule.every(v)
                    } else if (let Some(v) <- atOpt) {
                        j.schedule = CronSchedule.at(v)
                    } else if (let Some(v) <- cronExprOpt) {
                        let tzUse = if (let Some(tv) <- tzOpt) { tv } else if (j.schedule.timeZone.trimAscii().isEmpty()) { "UTC" } else { j.schedule.timeZone }
                        j.schedule = CronSchedule.cron(v, tzUse, staggerMs: j.schedule.staggerMs)
                    } else if (let Some(tv) <- tzOpt) {
                        if (j.schedule.kind.trimAscii().toAsciiLower() == "cron") {
                            j.schedule = CronSchedule.cron(j.schedule.cronExpr, tv, staggerMs: j.schedule.staggerMs)
                        }
                    }
                    if (staggerExactPatch || staggerMsPatch.isSome()) {
                        let sk = j.schedule.kind.trimAscii().toAsciiLower()
                        if (sk != "cron") {
                            return cronErr("invalid cron.update params: stagger applies only to cron schedules")
                        }
                        let sm = if (staggerExactPatch) {
                            0
                        } else if (let Some(s) <- staggerMsPatch) {
                            s
                        } else {
                            j.schedule.staggerMs
                        }
                        j.schedule = CronSchedule.cron(j.schedule.cronExpr, j.schedule.timeZone, staggerMs: sm)
                    }

                    match (computeJobNextRun(j, nowMs)) {
                        case Some(nxt) => j.state.nextRunAtMs = nxt
                        case None => j.state.nextRunAtMs = 0
                    }
                    updatedJob = Some(j)
                }
                list.add(j)
            }
            if (!found) {
                return cronErr("invalid cron.update params: unknown id")
            }
            cronSave(path, list.toArray())
            match (updatedJob) {
                case Some(j) => cronJobCommandOutput("updated", j, path, json)
                case None =>
                    cronJobCommandOutput("updated", CronJob(jobId, "", CronSchedule.every(60000), createdAtMs: 0), path, json)
            }
        case None => cronErr("invalid cron.update params: missing id")
    }
}

private func cronCmdRuns(path: Path, sub: Array<String>): (String, Int64) {
    let targetId = match (parseJobIdFlag(sub, 2)) {
        case Some(v) => v
        case None => ""
    }
    let json = cronArgvHasJsonFlag(sub, 2)
    var limit: Int64 = 50
    var offset: Int64 = 0
    var i: Int64 = 2
    while (i < sub.size) {
        let k = sub[i].trimAscii().toAsciiLower()
        if (k == "--json") {
            i += 1
            continue
        }
        if (k == "--limit" && i + 1 < sub.size) {
            try {
                let v = Int64.parse(sub[i + 1].trimAscii())
                if (v > 0) {
                    limit = v
                }
            } catch (_: Exception) {
                ()
            }
            i += 2
            continue
        }
        if (k == "--offset" && i + 1 < sub.size) {
            try {
                let v = Int64.parse(sub[i + 1].trimAscii())
                if (v >= 0) {
                    offset = v
                }
            } catch (_: Exception) {
                ()
            }
            i += 2
            continue
        }
        i += 1
    }
    if (!targetId.isEmpty()) {
        let page = readCronRunLogEntriesForJob(path, targetId, limit: limit, offset: offset)
        if (json) {
            return (page.toJsonString(), 0)
        }
        return (formatCronRunsPageForHuman(page, targetId), 0)
    }
    let all = ArrayList<JsonValue>()
    for (j in cronLoadOrEmpty(path)) {
        // 先读取每个任务的全部条目，之后做全局排序和分页。
        let one = readCronRunLogEntriesForJob(path, j.id, limit: 10_000, offset: 0)
        for (it in one.get("entries").getOrThrow().asArray().getItems()) {
            all.add(it)
        }
    }
    // 全局按 ts 倒序。
    let sorted = ArrayList<JsonValue>()
    for (it in all) {
        sorted.add(it)
    }
    sort(sorted, by: { a, b =>
        let ao = a.asObject()
        let bo = b.asObject()
        let ats = match (ao.get("ts")) {
            case Some(v) => v.asInt().getValue()
            case None => 0
        }
        let bts = match (bo.get("ts")) {
            case Some(v) => v.asInt().getValue()
            case None => 0
        }
        bts.compare(ats)
    }, stable: true)
    let total = sorted.size
    let lim = if (limit > 0) { limit } else { 1 }
    var off = if (offset >= 0) { offset } else { 0 }
    if (off > total) {
        off = total
    }
    var end = off + lim
    if (end > total) {
        end = total
    }
    let pageEntries = ArrayList<JsonValue>()
    var p = off
    while (p < end) {
        pageEntries.add(sorted[p])
        p += 1
    }
    let outAll = JsonObject()
    outAll.put("entries", JsonArray(pageEntries))
    outAll.put("total", JsonInt(total))
    outAll.put("offset", JsonInt(off))
    outAll.put("limit", JsonInt(lim))
    outAll.put("hasMore", JsonBool(end < total))
    outAll.put("nextOffset", if (end < total) { JsonInt(end) } else { JsonValue.fromStr("null") })
    if (json) {
        return (outAll.toJsonString(), 0)
    }
    (formatCronRunsPageForHuman(outAll, ""), 0)
}

private func jsonObjString(o: JsonObject, key: String): String {
    match (o.get(key)) {
        case Some(v) => try {
            v.asString().getValue()
        } catch (_: Exception) {
            ""
        }
        case None => ""
    }
}

private func jsonObjInt(o: JsonObject, key: String): Int64 {
    match (o.get(key)) {
        case Some(v) => try {
            v.asInt().getValue()
        } catch (_: Exception) {
            0
        }
        case None => 0
    }
}

private func formatCronRunsPageForHuman(page: JsonObject, targetId: String): String {
    let entries = page.get("entries").getOrThrow().asArray()
    let total = jsonObjInt(page, "total")
    if (entries.size() == 0) {
        return if (targetId.isEmpty()) {
            "No cron runs."
        } else {
            "No cron runs for ${targetId}."
        }
    }
    let lines = ArrayList<String>()
    let scope = if (targetId.isEmpty()) { "all jobs" } else { targetId }
    lines.add("Cron runs (${scope})")
    lines.add("Showing ${entries.size()} of ${total} run(s).")
    lines.add(
        padRight("TS", 14) + " " +
            padRight("Job ID", 28) + " " +
            padRight("Status", 8) + " " +
            padRight("Duration", 10) + " " +
            padRight("Delivery", 14) + " " +
            "Summary"
    )
    for (it in entries.getItems()) {
        let row = it.asObject()
        lines.add(
            padRight("${jsonObjInt(row, "ts")}", 14) + " " +
                padRight(ellipsis(jsonObjString(row, "jobId"), 28), 28) + " " +
                padRight(ellipsis(jsonObjString(row, "status"), 8), 8) + " " +
                padRight("${jsonObjInt(row, "durationMs")}ms", 10) + " " +
                padRight(ellipsis(jsonObjString(row, "deliveryStatus"), 14), 14) + " " +
                ellipsis(jsonObjString(row, "summary"), 60)
        )
    }
    String.join(lines.toArray(), delimiter: "\n")
}

private func cronCmdWake(path: Path, sub: Array<String>): (String, Int64) {
    let targetId = match (parseJobIdFlag(sub, 2)) {
        case Some(v) => v
        case None => ""
    }
    let json = cronArgvHasJsonFlag(sub, 2)
    var mode = "now"
    var textHint = ""
    var i: Int64 = 2
    while (i < sub.size) {
        let k = sub[i].trimAscii().toAsciiLower()
        if (k == "--json") {
            i += 1
            continue
        }
        if (k == "--mode" && i + 1 < sub.size) {
            let v = sub[i + 1].trimAscii().toAsciiLower()
            if (!v.isEmpty()) {
                mode = v
            }
            i += 2
            continue
        }
        if (k == "--text" && i + 1 < sub.size) {
            textHint = sub[i + 1].trimAscii()
            i += 2
            continue
        }
        i += 1
    }
    if (textHint.isEmpty()) {
        if (json) { return ("{\"ok\":false,\"error\":\"missing --text\"}", 1) }
        return ("Cron wake skipped\nReason: --text is required.", 1)
    }
    let list = ArrayList<CronJob>()
    var count: Int64 = 0
    let nowMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
    let wakeAt = if (mode == "next-heartbeat") {
        nowMs + 10_000
    } else {
        nowMs
    }
    for (j in cronLoadOrEmpty(path)) {
        if (!targetId.isEmpty() && j.id != targetId) {
            list.add(j)
            continue
        }
        if (j.enabled) {
            j.state.nextRunAtMs = wakeAt
            count += 1
        }
        list.add(j)
    }
    if (count == 0) {
        return cronErr("wake failed: no enabled jobs matched")
    }
    cronSave(path, list.toArray())
    if (!json) {
        let lines = ArrayList<String>()
        lines.add("Cron wake updated")
        lines.add("Matched enabled jobs: ${count}")
        lines.add("Mode: ${mode}")
        lines.add("Wake at: ${wakeAt}")
        if (!targetId.isEmpty()) { lines.add("Job: ${targetId}") }
        return (String.join(lines.toArray(), delimiter: "\n"), 0)
    }
    let out = JsonObject()
    out.put("ok", JsonBool(!textHint.isEmpty()))
    out.put("matched", JsonInt(count))
    out.put("mode", JsonString(mode))
    out.put("wakeAtMs", JsonInt(wakeAt))
    (out.toJsonString(), 0)
}

private func cronCmdRemove(path: Path, sub: Array<String>): (String, Int64) {
    if (sub.size < 3) {
        return cronErr("invalid cron.remove params")
    }
    var id = ""
    if (sub.size >= 4) {
        let flag = sub[2].trimAscii().toAsciiLower()
        if (flag == "--job-id" || flag == "--id") {
            id = sub[3].trimAscii()
        } else {
            id = sub[2].trimAscii()
        }
    } else {
        id = sub[2].trimAscii()
    }
    if (id.isEmpty()) {
        return cronErr("invalid cron.remove params: missing id")
    }
    let list = ArrayList<CronJob>()
    var found = false
    for (j in cronLoadOrEmpty(path)) {
        if (j.id == id) {
            found = true
        } else {
            list.add(j)
        }
    }
    if (!found) {
        return ("{\"ok\":true,\"removed\":false}", 0)
    }
    cronSave(path, list.toArray())
    return ("{\"ok\":true,\"removed\":true}", 0)
}

private func cronCmdSetEnabled(path: Path, sub: Array<String>, enabled: Bool): (String, Int64) {
    if (sub.size < 3) {
        let verb = if (enabled) {
            "enable"
        } else {
            "disable"
        }
        return ("用法: gateway cron ${verb} <id>", 1)
    }
    let id = sub[2].trimAscii()
    if (id.isEmpty()) {
        return ("id 不能为空。", 1)
    }
    let list = ArrayList<CronJob>()
    var found = false
    for (j in cronLoadOrEmpty(path)) {
        if (j.id == id) {
            j.enabled = enabled
            found = true
        }
        list.add(j)
    }
    if (!found) {
        return ("未找到 id=${id}。", 1)
    }
    cronSave(path, list.toArray())
    let st = if (enabled) {
        "已启用"
    } else {
        "已禁用"
    }
    return ("${st} id=${id}。\n→ ${path.toString()}", 0)
}

/**
 * Dashboard 保存对现有任务的修改：更新 `prompt` / `sessionTarget` / `enabled` / `schedule`，
 * **保留** `state` 中的 `lastRunAtMs`、`lastError`；仅重新计算 `nextRunAtMs` 以匹配新调度。
 */
public func cronDashboardSaveJob(
    path: Path,
    jobId: String,
    prompt: String,
    sessionTarget: String,
    enabled: Bool,
    scheduleKind: String,
    everyRaw: String,
    atRaw: String,
    cronExpr: String,
    timeZone: String,
    systemEvent: String,
    wakeMode: String,
    deliveryChannel: String,
    deliveryTo: String,
    deliveryAnnounce: Bool
): (String, Int64) {
    let id = jobId.trimAscii()
    if (id.isEmpty()) {
        return ("jobId 不能为空。", 1)
    }
    let list = ArrayList<CronJob>()
    var found = false
    for (j in cronLoadOrEmpty(path)) {
        if (j.id == id) {
            found = true
        }
        list.add(j)
    }
    if (!found) {
        return ("未找到 id=${id}。", 1)
    }

    let sk = scheduleKind.trimAscii().toAsciiLower()
    var newSch: CronSchedule
    if (sk == "at") {
        match (parseAtToUnixMs(atRaw)) {
            case Some(atv) =>
                if (atv <= 0) {
                    return ("at 时间无效。", 1)
                }
                newSch = CronSchedule.at(atv)
            case None => return ("无法解析 at 时间。", 1)
        }
    } else if (sk == "cron") {
        let ce = cronExpr.trimAscii()
        if (!isValidCronFiveExpression(ce)) {
            return ("cron 五段式非法。", 1)
        }
        let tz = timeZone.trimAscii()
        if (tz.isEmpty()) {
            return ("请填写时区（如 UTC 或 UTC+8）。", 1)
        }
        if (cronResolveTimeZoneOffsetMinutes(tz).isNone()) {
            return ("无法解析时区。", 1)
        }
        newSch = CronSchedule.cron(ce, tz)
    } else {
        match (parseDurationOrMs(everyRaw)) {
            case Some(ev) =>
                if (ev <= 0) {
                    return ("every 须为正数。", 1)
                }
                newSch = CronSchedule.every(ev)
            case None => return ("无法解析 every 间隔。", 1)
        }
    }

    let nowMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
    for (j in list) {
        if (j.id != id) {
            continue
        }
        j.prompt = prompt
        j.sessionTarget = sessionTarget.trimAscii()
        j.enabled = enabled
        j.schedule = newSch
        j.systemEvent = systemEvent.trimAscii()
        j.wakeMode = wakeMode.trimAscii()
        j.deliveryChannel = deliveryChannel.trimAscii()
        j.deliveryTo = deliveryTo.trimAscii()
        j.deliveryAnnounce = deliveryAnnounce
        match (computeJobNextRun(j, nowMs)) {
            case Some(nxt) => j.state.nextRunAtMs = nxt
            case None => j.state.nextRunAtMs = 0
        }
        break
    }
    cronSave(path, list.toArray())
    return ("已保存任务 id=${id}。\n→ ${path.toString()}", 0)
}
