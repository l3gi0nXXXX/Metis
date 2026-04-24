package metis.cron

import magic.log.LogUtils

import std.collection.ArrayList
import std.fs.{Path, File, Directory, exists, copy, remove}
import std.time.DateTime
import stdx.encoding.json.*

private let STORE_VERSION: Int64 = 1
private let STORE_DIR: String = "cron"
private let FILE_NAME: String = "jobs.json"

private func readStr(o: JsonObject, key: String, default!: String = ""): String {
    match (o.get(key)) {
        case Some(v) => match (v) {
            case s: JsonString => s.getValue()
            case _ => default
        }
        case None => default
    }
}

private func readI64(o: JsonObject, key: String, default!: Int64 = 0): Int64 {
    match (o.get(key)) {
        case Some(v) => match (v) {
            case n: JsonInt => n.getValue()
            case n: JsonFloat => Int64(n.getValue())
            case _ => default
        }
        case None => default
    }
}

private func readBool(o: JsonObject, key: String, default!: Bool = false): Bool {
    match (o.get(key)) {
        case Some(v) => match (v) {
            case b: JsonBool => b.getValue()
            case s: JsonString =>
                let t = s.getValue().trimAscii().toAsciiLower()
                t == "1" || t == "true" || t == "yes"
            case n: JsonInt => n.getValue() != 0
            case _ => default
        }
        case None => default
    }
}

private func parseSchedule(obj: JsonObject): CronSchedule {
    let kind = readStr(obj, "kind", default: "every").trimAscii().toAsciiLower()
    let everyMs = readI64(obj, "everyMs", default: 3600000)
    let anchorMs = readI64(obj, "anchorMs", default: 0)
    let atMs = readI64(obj, "atMs", default: 0)
    let cronExpr = readStr(obj, "cronExpr", default: "")
    let timeZone = readStr(obj, "timeZone", default: "UTC")
    let staggerMs = readI64(obj, "staggerMs", default: 0)
    CronSchedule(kind, everyMs, anchorMs, atMs, cronExpr, timeZone, staggerMs)
}

private func parseState(obj: JsonObject): CronJobState {
    CronJobState(
        nextRunAtMs: readI64(obj, "nextRunAtMs", default: 0),
        lastRunAtMs: readI64(obj, "lastRunAtMs", default: 0),
        lastError: readStr(obj, "lastError", default: ""),
        lastStatus: readStr(obj, "lastStatus", default: ""),
        consecutiveErrors: readI64(obj, "consecutiveErrors", default: 0),
        runningAtMs: readI64(obj, "runningAtMs", default: 0),
        scheduleErrorCount: readI64(obj, "scheduleErrorCount", default: 0),
        lastFailureAlertAtMs: readI64(obj, "lastFailureAlertAtMs", default: 0)
    )
}

private func parseJob(obj: JsonObject): Option<CronJob> {
    let id = readStr(obj, "id", default: "").trimAscii()
    if (id.isEmpty()) {
        return None<CronJob>
    }
    let prompt = readStr(obj, "prompt", default: "")
    let st = match (obj.get("schedule")) {
        case Some(sv) => try {
            parseSchedule(sv.asObject())
        } catch (_: Exception) {
            CronSchedule.every(3600000)
        }
        case None => CronSchedule.every(3600000)
    }
    let state = match (obj.get("state")) {
        case Some(sv) => try {
            parseState(sv.asObject())
        } catch (_: Exception) {
            CronJobState()
        }
        case None => CronJobState()
    }
    Some(
        CronJob(
            id,
            prompt,
            st,
            createdAtMs: readI64(obj, "createdAtMs", default: 0),
            enabled: readBool(obj, "enabled", default: true),
            sessionTarget: readStr(obj, "sessionTarget", default: "main"),
            state: state,
            systemEvent: readStr(obj, "systemEvent", default: ""),
            wakeMode: readStr(obj, "wakeMode", default: ""),
            deliveryChannel: readStr(obj, "deliveryChannel", default: ""),
            deliveryTo: readStr(obj, "deliveryTo", default: ""),
            deliveryAnnounce: readBool(obj, "deliveryAnnounce", default: false),
            timeoutMs: readI64(obj, "timeoutMs", default: 0),
            maxRetries: readI64(obj, "maxRetries", default: 0),
            retryBackoffMs: readI64(obj, "retryBackoffMs", default: 1000),
            failureChannel: readStr(obj, "failureChannel", default: ""),
            failureTo: readStr(obj, "failureTo", default: ""),
            failureAnnounce: readBool(obj, "failureAnnounce", default: true),
            payloadKind: readStr(obj, "payloadKind", default: "agentTurn"),
            deliveryMode: readStr(obj, "deliveryMode", default: ""),
            failureDestMode: readStr(obj, "failureDestMode", default: ""),
            deleteAfterRun: readBool(obj, "deleteAfterRun", default: false),
            updatedAtMs: readI64(obj, "updatedAtMs", default: 0),
            description: readStr(obj, "description", default: ""),
            agentId: readStr(obj, "agentId", default: ""),
            sessionKey: readStr(obj, "sessionKey", default: ""),
            modelOverride: readStr(obj, "modelOverride", default: ""),
            thinkingLevel: readStr(obj, "thinkingLevel", default: ""),
            lightContext: readBool(obj, "lightContext", default: false),
            deliveryAccountId: readStr(obj, "deliveryAccountId", default: ""),
            bestEffortDeliver: readBool(obj, "bestEffortDeliver", default: false),
            failureAccountId: readStr(obj, "failureAccountId", default: ""),
            failureAlertAfter: readI64(obj, "failureAlertAfter", default: 0),
            failureAlertCooldownMs: readI64(obj, "failureAlertCooldownMs", default: 0)
        )
    )
}

/**
 * 持久化路径：`<CliConfig.dotDir>/cron/jobs.json`（与参考实现的 `cron/jobs.json` 布局一致）。
 */
public func cronStorePath(dotDir: Path): Path {
    dotDir.join(STORE_DIR).join(FILE_NAME)
}

public func cronLoadOrEmpty(path: Path): Array<CronJob> {
    if (!exists(path)) {
        return Array<CronJob>()
    }
    try {
        let text = String.fromUtf8(File.readFrom(path))
        let root = JsonValue.fromStr(text).asObject()
        let ver = readI64(root, "version", default: 0)
        if (ver != STORE_VERSION) {
            LogUtils.info("CronStore: version mismatch (got ${ver}, expect ${STORE_VERSION}), still trying to parse jobs")
        }
        let list = ArrayList<CronJob>()
        match (root.get("jobs")) {
            case Some(jv) =>
                let arr = jv.asArray()
                for (item in arr.getItems()) {
                    try {
                        match (parseJob(item.asObject())) {
                            case Some(j) => list.add(j)
                            case None => ()
                        }
                    } catch (_: Exception) {
                        ()
                    }
                }
            case None => ()
        }
        list.toArray()
    } catch (e: Exception) {
        LogUtils.error("CronStore: load failed: ${e.message}")
        Array<CronJob>()
    }
}

private func scheduleToJson(s: CronSchedule): JsonObject {
    let o = JsonObject()
    o.put("kind", JsonString(s.kind))
    o.put("everyMs", JsonInt(s.everyMs))
    o.put("anchorMs", JsonInt(s.anchorMs))
    o.put("atMs", JsonInt(s.atMs))
    o.put("cronExpr", JsonString(s.cronExpr))
    o.put("timeZone", JsonString(s.timeZone))
    o.put("staggerMs", JsonInt(s.staggerMs))
    o
}

private func stateToJson(st: CronJobState): JsonObject {
    let o = JsonObject()
    o.put("nextRunAtMs", JsonInt(st.nextRunAtMs))
    o.put("lastRunAtMs", JsonInt(st.lastRunAtMs))
    o.put("lastError", JsonString(st.lastError))
    o.put("lastStatus", JsonString(st.lastStatus))
    o.put("consecutiveErrors", JsonInt(st.consecutiveErrors))
    o.put("runningAtMs", JsonInt(st.runningAtMs))
    o.put("scheduleErrorCount", JsonInt(st.scheduleErrorCount))
    o.put("lastFailureAlertAtMs", JsonInt(st.lastFailureAlertAtMs))
    o
}

private func jobToJson(j: CronJob): JsonObject {
    let o = JsonObject()
    o.put("id", JsonString(j.id))
    o.put("createdAtMs", JsonInt(j.createdAtMs))
    o.put("enabled", JsonBool(j.enabled))
    o.put("prompt", JsonString(j.prompt))
    o.put("schedule", scheduleToJson(j.schedule))
    o.put("sessionTarget", JsonString(j.sessionTarget))
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
    o.put("state", stateToJson(j.state))
    o
}

private func buildStoreJsonBytes(jobs: Array<CronJob>): Array<UInt8> {
    let root = JsonObject()
    root.put("version", JsonInt(STORE_VERSION))
    let arr = ArrayList<JsonValue>()
    for (j in jobs) {
        arr.add(jobToJson(j))
    }
    root.put("jobs", JsonArray(arr))
    root.toJsonString().toArray()
}

/** 持久化任务列表；与参考实现一致采用临时文件 + 备份 + 替换。 */
public func cronSave(path: Path, jobs: Array<CronJob>): Unit {
    cronSaveAtomic(path, jobs)
}

/**
 * 与参考实现的 `saveCronStore` 类似：先写临时文件、尽力备份 `.bak`、再替换目标文件。
 */
public func cronSaveAtomic(path: Path, jobs: Array<CronJob>): Unit {
    let parent = path.parent
    if (!exists(parent)) {
        Directory.create(parent, recursive: true)
    }
    let bytes = buildStoreJsonBytes(jobs)
    let stamp = DateTime.now().toUnixTimeStamp().toMilliseconds()
    let tmp = parent.join("${FILE_NAME}.${stamp}.tmp")
    File.writeTo(tmp, bytes)
    let bak = parent.join("${FILE_NAME}.bak")
    if (exists(path)) {
        try {
            copy(path, to: bak, overwrite: true)
        } catch (_: Exception) {
            ()
        }
    }
    try {
        if (exists(path)) {
            remove(path)
        }
    } catch (_: Exception) {
        ()
    }
    copy(tmp, to: path, overwrite: true)
    try {
        remove(tmp)
    } catch (_: Exception) {
        ()
    }
}
