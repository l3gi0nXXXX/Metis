package metis.gateway.runtime

import metis.core.config.{CliConfig, CliSettingManager}
import metis.cron.cronStorePath

import stdx.encoding.json.{JsonBool, JsonObject, JsonString, JsonValue}

private func gatewayParseCronRunJobIdAndDue(sub: Array<String>): (Option<String>, Bool) {
    var dueOnly = false
    var jobFromPos: Option<String> = None<String>
    if (sub.size > 2) {
        let t = sub[2].trimAscii()
        if (!t.startsWith("--")) {
            jobFromPos = Some(t)
        }
    }
    let jobIdOpt = if (jobFromPos.isSome()) {
        jobFromPos
    } else {
        gatewayParseJobIdFlag(sub, 2)
    }
    var i: Int64 = 2
    while (i < sub.size) {
        if (sub[i].trimAscii().toAsciiLower() == "--due") {
            dueOnly = true
        }
        i += 1
    }
    (jobIdOpt, dueOnly)
}

private func gatewayParseJobIdFlag(sub: Array<String>, start: Int64): Option<String> {
    var idx = start
    while (idx < sub.size) {
        let k = sub[idx].trimAscii().toAsciiLower()
        if (k == "--job-id" || k == "--id") {
            if (idx + 1 >= sub.size) {
                return None<String>
            }
            let v = sub[idx + 1].trimAscii()
            if (v.isEmpty()) {
                return None<String>
            }
            return Some(v)
        }
        idx += 1
    }
    None<String>
}

private func cronRunResultExitCode(obj: JsonObject): Int64 {
    let ok = match (obj.get("ok")) {
        case Some(v) =>
            match (v) {
                case b: JsonBool => b.getValue()
                case _ => false
            }
        case None => false
    }
    let ran = match (obj.get("ran")) {
        case Some(v) =>
            match (v) {
                case b: JsonBool => b.getValue()
                case _ => false
            }
        case None => false
    }
    if (ok && ran) {
        return 0
    }
    1
}

/**
 * 与 tick / `cron run` 同源：拉起本地 `GatewayService`，对指定任务执行一次并持久化（含投递、失败告警等）。
 */
public func gatewayCronExecuteJobOnce(jobId: String, force: Bool): JsonObject {
    let user = CliSettingManager.readGatewaySettings()
    let (gw, _) = buildGatewayServiceFromUserSettings(user)
    try {
        gw.start()
    } catch (_: Exception) {
        ()
    }
    let jo = CronRunner.runJobOnceFromStore(
        Some(gw),
        cronStorePath(CliConfig.dotDir),
        jobId,
        force,
        cronEnabled: user.cronEnabled
    )
    try {
        gw.stop()
    } catch (_: Exception) {
        ()
    }
    jo
}

/** Dashboard / Control UI：将执行结果转为 `(成功, 说明)`。 */
public func gatewayCronRunOnceOutcome(jobId: String, force: Bool): (Bool, String) {
    let jo = gatewayCronExecuteJobOnce(jobId, force)
    let ok = match (jo.get("ok")) {
        case Some(v) =>
            match (v) {
                case b: JsonBool => b.getValue()
                case _ => false
            }
        case None => false
    }
    let ran = match (jo.get("ran")) {
        case Some(v) =>
            match (v) {
                case b: JsonBool => b.getValue()
                case _ => false
            }
        case None => false
    }
    if (ok && ran) {
        return (true, "已立即运行任务 id=${jobId}")
    }
    let err = match (jo.get("error")) {
        case Some(s: JsonString) => s.getValue()
        case _ => ""
    }
    if (!err.isEmpty()) {
        return (false, err)
    }
    let reason = match (jo.get("reason")) {
        case Some(s: JsonString) => s.getValue()
        case _ => ""
    }
    if (!reason.isEmpty()) {
        return (false, reason)
    }
    (false, jo.toJsonString())
}

/**
 * 与 `CronRunner.runJobManual` 同源：本地组 `GatewayService` + `AgentBridge` 执行一次任务（不依赖仅 wake）。
 */
public func gatewayCronRunUnified(sub: Array<String>): (String, Int64) {
    let (jobIdOpt, dueOnly) = gatewayParseCronRunJobIdAndDue(sub)
    match (jobIdOpt) {
        case None =>
            let err = JsonObject()
            err.put("ok", JsonBool(false))
            err.put("error", JsonString("missing id (cron run <id> or --job-id <id>)"))
            (err.toJsonString(), 1)
        case Some(jobId) =>
            let jo = gatewayCronExecuteJobOnce(jobId, !dueOnly)
            (jo.toJsonString(), cronRunResultExitCode(jo))
    }
}
