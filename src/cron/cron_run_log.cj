package metis.cron

import std.collection.ArrayList
import std.fs.{Directory, File, Path, exists}
import std.sort.sort
import stdx.encoding.json.{JsonArray, JsonBool, JsonFloat, JsonInt, JsonObject, JsonString, JsonValue}

private let DEFAULT_RUNS_LIMIT: Int64 = 50

private func jsonEscape(raw: String): String {
    raw.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")
}

/** 与参考实现的 `resolveCronRunLogPath` 一致：`jobs.json` 同目录下的 `runs/`。 */
public func cronRunsDirFromStore(storePath: Path): Path {
    storePath.parent.join("runs")
}

public func cronRunLogPathFromStore(storePath: Path, jobId: String): Path {
    cronRunsDirFromStore(storePath).join("${jobId}.jsonl")
}

public func appendCronRunLog(
    storePath: Path,
    jobId: String,
    status: String,
    startedAtMs: Int64,
    endedAtMs: Int64,
    errorMessage!: String = "",
    sessionTarget!: String = "",
    summary!: String = "",
    runAtMs!: Int64 = 0,
    nextRunAtMs!: Int64 = 0,
    deliveryStatus!: String = "not-requested"
): Unit {
    let dir = cronRunsDirFromStore(storePath)
    if (!exists(dir)) {
        Directory.create(dir, recursive: true)
    }
    let p = cronRunLogPathFromStore(storePath, jobId)
    let durationMs = if (endedAtMs >= startedAtMs) { endedAtMs - startedAtMs } else { 0 }
    let line = "{" +
        "\"ts\":${endedAtMs}," +
        "\"jobId\":\"${jsonEscape(jobId)}\"," +
        "\"action\":\"finished\"," +
        "\"status\":\"${jsonEscape(status)}\"," +
        "\"summary\":\"${jsonEscape(summary)}\"," +
        "\"runAtMs\":${if (runAtMs > 0) { runAtMs } else { startedAtMs }}," +
        "\"startedAtMs\":${startedAtMs}," +
        "\"endedAtMs\":${endedAtMs}," +
        "\"durationMs\":${durationMs}," +
        "\"nextRunAtMs\":${nextRunAtMs}," +
        "\"deliveryStatus\":\"${jsonEscape(deliveryStatus)}\"," +
        "\"sessionTarget\":\"${jsonEscape(sessionTarget)}\"," +
        "\"error\":\"${jsonEscape(errorMessage)}\"" +
        "}\n"
    if (exists(p)) {
        let old = String.fromUtf8(File.readFrom(p))
        File.writeTo(p, (old + line).toArray())
    } else {
        File.writeTo(p, line.toArray())
    }
}

private func runLogReadI64(o: JsonObject, key: String, default!: Int64 = 0): Int64 {
    match (o.get(key)) {
        case Some(v) => match (v) {
            case n: JsonInt => n.getValue()
            case n: JsonFloat => Int64(n.getValue())
            case _ => default
        }
        case None => default
    }
}

private func runLogReadStr(o: JsonObject, key: String, default!: String = ""): String {
    match (o.get(key)) {
        case Some(v) => match (v) {
            case s: JsonString => s.getValue()
            case b: JsonBool => if (b.getValue()) { "true" } else { "false" }
            case _ => default
        }
        case None => default
    }
}

public func readCronRunLogEntriesForJob(
    storePath: Path,
    jobId: String,
    limit!: Int64 = DEFAULT_RUNS_LIMIT,
    offset!: Int64 = 0
): JsonObject {
    let p = cronRunLogPathFromStore(storePath, jobId)
    if (!exists(p)) {
        let empty = JsonObject()
        empty.put("entries", JsonArray(ArrayList<JsonValue>()))
        empty.put("total", JsonInt(0))
        empty.put("offset", JsonInt(0))
        empty.put("limit", JsonInt(limit))
        empty.put("hasMore", JsonBool(false))
        empty.put("nextOffset", JsonValue.fromStr("null"))
        return empty
    }
    let text = String.fromUtf8(File.readFrom(p))
    let rows = ArrayList<JsonObject>()
    for (line in text.split("\n")) {
        let t = line.trimAscii()
        if (t.isEmpty()) {
            continue
        }
        try {
            rows.add(JsonValue.fromStr(t).asObject())
        } catch (_: Exception) {
            ()
        }
    }
    let total = rows.size
    let off = min(max(0, offset), total)
    let lim = max(1, limit)
    let end = min(off + lim, total)
    let out = ArrayList<JsonValue>()
    // 参考实现风格：默认展示最近记录优先（按 ts 倒序）。
    var i = total - 1 - off
    var emitted: Int64 = 0
    while (i >= 0 && emitted < (end - off)) {
        let raw = rows[i]
        let row = JsonObject()
        row.put("ts", JsonInt(runLogReadI64(raw, "ts", default: runLogReadI64(raw, "endedAtMs"))))
        row.put("jobId", JsonString(runLogReadStr(raw, "jobId")))
        row.put("action", JsonString(runLogReadStr(raw, "action", default: "finished")))
        let st = runLogReadStr(raw, "status")
        row.put("status", JsonString(if (st == "success") { "ok" } else { st }))
        let sum = runLogReadStr(raw, "summary")
        let err = runLogReadStr(raw, "error")
        row.put("summary", JsonString(if (!sum.isEmpty()) { sum } else { err }))
        row.put("runAtMs", JsonInt(runLogReadI64(raw, "runAtMs", default: runLogReadI64(raw, "startedAtMs"))))
        row.put("durationMs", JsonInt(runLogReadI64(raw, "durationMs")))
        row.put("nextRunAtMs", JsonInt(runLogReadI64(raw, "nextRunAtMs")))
        row.put("deliveryStatus", JsonString(runLogReadStr(raw, "deliveryStatus", default: "not-requested")))
        out.add(row)
        i -= 1
        emitted += 1
    }
    let result = JsonObject()
    result.put("entries", JsonArray(out))
    result.put("total", JsonInt(total))
    result.put("offset", JsonInt(off))
    result.put("limit", JsonInt(lim))
    result.put("hasMore", JsonBool(end < total))
    result.put("nextOffset", if (end < total) { JsonInt(end) } else { JsonValue.fromStr("null") })
    result
}

/**
 * 合并多个任务的运行记录，按 `ts` 降序，供 Dashboard 等一次性展示。
 * `resultLimit` 为返回条数上限（减轻 JSON 体积）；`total` 仍为合并后的总条数。
 */
public func readCronRunLogMergedFromStore(
    storePath: Path,
    jobIds: Array<String>,
    resultLimit!: Int64 = 800
): JsonObject {
    let all = ArrayList<JsonValue>()
    for (jid in jobIds) {
        let one = readCronRunLogEntriesForJob(storePath, jid, limit: 50_000, offset: 0)
        match (one.get("entries")) {
            case Some(jv) =>
                for (it in jv.asArray().getItems()) {
                    all.add(it)
                }
            case None => ()
        }
    }
    let sorted = ArrayList<JsonValue>()
    for (it in all) {
        sorted.add(it)
    }
    sort(
        sorted,
        by: { a, b =>
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
        },
        stable: true
    )
    let total = sorted.size
    var lim = resultLimit
    if (lim <= 0) {
        lim = 1
    }
    let cap = min(lim, total)
    let page = ArrayList<JsonValue>()
    var i: Int64 = 0
    while (i < cap) {
        page.add(sorted[i])
        i += 1
    }
    let out = JsonObject()
    out.put("entries", JsonArray(page))
    out.put("total", JsonInt(total))
    out.put("returned", JsonInt(cap))
    out
}
