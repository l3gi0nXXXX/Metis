package metis.cron

import std.collection.ArrayList

/** 与参考实现的 `stagger.ts` `DEFAULT_TOP_OF_HOUR_STAGGER_MS` 一致 */
public let DEFAULT_TOP_OF_HOUR_STAGGER_MS: Int64 = 5 * 60 * 1000

private func parseCronFields(expr: String): Array<String> {
    let raw = expr.trimAscii().split(" ")
    let out = ArrayList<String>()
    for (seg in raw) {
        let t = seg.trimAscii()
        if (!t.isEmpty()) {
            out.add(t)
        }
    }
    out.toArray()
}

/** 与参考实现的 `isRecurringTopOfHourCronExpr` 对齐（五段 / 六段首字段为秒时） */
public func isRecurringTopOfHourCronExpr(expr: String): Bool {
    let fields = parseCronFields(expr)
    if (fields.size == 5) {
        let minute = fields[0].trimAscii()
        let hour = fields[1].trimAscii()
        return minute == "0" && hour.contains("*")
    }
    if (fields.size == 6) {
        let second = fields[0].trimAscii()
        let minute = fields[1].trimAscii()
        let hour = fields[2].trimAscii()
        return second == "0" && minute == "0" && hour.contains("*")
    }
    false
}

public func normalizeCronStaggerMs(raw: Int64): Int64 {
    if (raw < 0) {
        return 0
    }
    raw
}

public func resolveDefaultCronStaggerMs(expr: String): Int64 {
    if (isRecurringTopOfHourCronExpr(expr)) {
        return DEFAULT_TOP_OF_HOUR_STAGGER_MS
    }
    0
}

/** 有效 stagger：显式字段优先，否则整点类表达式默认 5min */
public func resolveCronStaggerMsForExpr(expr: String, explicitStaggerMs: Int64): Int64 {
    let ex = normalizeCronStaggerMs(explicitStaggerMs)
    if (ex > 0) {
        return ex
    }
    resolveDefaultCronStaggerMs(expr.trimAscii())
}

public func resolveCronStaggerMs(schedule: CronSchedule): Int64 {
    let sk = schedule.kind.trimAscii().toAsciiLower()
    if (sk != "cron") {
        return 0
    }
    resolveCronStaggerMsForExpr(schedule.cronExpr, schedule.staggerMs)
}

/**
 * 与参考实现的 `resolveStableCronOffsetMs` 同语义：SHA256 换成确定性 DJB2（不依赖 crypto）。
 */
public func stableCronStaggerOffsetMs(jobId: String, staggerMs: Int64): Int64 {
    if (staggerMs <= 1) {
        return 0
    }
    var hash: Int64 = 5381
    for (b in jobId.toArray()) {
        hash = ((hash << 5) + hash) + Int64(b)
    }
    var mod = hash % staggerMs
    if (mod < 0) {
        mod += staggerMs
    }
    mod
}

/**
 * 对齐参考实现的 `computeStaggeredCronNextRunAtMs`：在 cron 表达式匹配沿上叠加 per-job 稳定偏移。
 */
public func computeStaggeredCronNextRunAtMs(job: CronJob, nowMs: Int64): Option<Int64> {
    let sk = job.schedule.kind.trimAscii().toAsciiLower()
    if (sk != "cron") {
        return computeNextRunAtMs(job.schedule, nowMs, job.state.lastRunAtMs)
    }
    let staggerMs = resolveCronStaggerMs(job.schedule)
    let offsetMs = stableCronStaggerOffsetMs(job.id, staggerMs)
    if (offsetMs <= 0) {
        return computeNextRunAtMs(job.schedule, nowMs, job.state.lastRunAtMs)
    }
    var cursorMs = max(0, nowMs - offsetMs)
    var attempt: Int64 = 0
    while (attempt < 4) {
        match (computeNextRunAtMs(job.schedule, cursorMs, 0)) {
            case None => return None<Int64>
            case Some(baseNext) =>
                let shifted = baseNext + offsetMs
                if (shifted > nowMs) {
                    return Some(shifted)
                }
                cursorMs = max(cursorMs + 1, baseNext + 1000)
        }
        attempt += 1
    }
    None<Int64>
}
