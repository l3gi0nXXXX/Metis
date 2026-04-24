package metis.cron

/**
 * 计算「下一次」触发时间（Unix 毫秒），覆盖当前仓库的 every/at 调度语义。
 *
 * - `every`：在从未执行时按 anchor 与间隔对齐到未来第一个槽；执行后按 `lastRunAtMs + everyMs` 推进并跳过已过期槽。
 * - `at`：仅一次；若时刻已过且尚未执行，应尽快触发（由调用方将 next 置为 now）；执行后返回 `None` 表示不再调度。
 */
public func computeNextRunAtMs(schedule: CronSchedule, nowMs: Int64, lastRunAtMs: Int64): Option<Int64> {
    let k = schedule.kind.trimAscii().toAsciiLower()
    if (k == "cron") {
        let expr = schedule.cronExpr.trimAscii()
        if (expr.isEmpty()) {
            return Some(nowMs + 60_000)
        }
        let offMin = cronTimeZoneOffsetMinutesForSchedule(schedule.timeZone)
        return computeNextCronRunUtcMs(expr, offMin, nowMs, lastRunAtMs)
    }
    if (k == "at") {
        if (lastRunAtMs > 0) {
            return None<Int64>
        }
        let t = schedule.atMs
        if (t <= 0) {
            return None<Int64>
        }
        return Some(if (t > nowMs) {
            t
        } else {
            nowMs
        })
    }
    if (k != "every") {
        return Some(nowMs + 60_000)
    }
    let step = schedule.everyMs
    if (step <= 0) {
        return Some(nowMs + 60_000)
    }
    let anchor = schedule.anchorMs
    if (lastRunAtMs <= 0) {
        var base = if (anchor > 0) {
            anchor
        } else {
            nowMs
        }
        if (base <= nowMs) {
            let delta = nowMs - base
            let n = delta / step + 1
            base = base + n * step
        }
        return Some(base)
    }
    var nxt = lastRunAtMs + step
    while (nxt <= nowMs) {
        nxt += step
    }
    Some(nxt)
}

/** 某任务在 `nowMs` 是否到期（且仍为 every 或尚未执行的 at） */
public func isCronDue(state: CronJobState, nowMs: Int64, schedule: CronSchedule): Bool {
    if (state.nextRunAtMs <= 0) {
        return false
    }
    state.nextRunAtMs <= nowMs
}

/**
 * 在已知锚点下求下一触发（与 `ceil((now-anchor)/every)*every` 等价）。
 */
public func computeEveryNextFromAnchor(anchorMs: Int64, everyMs: Int64, nowMs: Int64): Int64 {
    let every = max(1, everyMs)
    let anchor = max(0, anchorMs)
    if (nowMs < anchor) {
        return anchor
    }
    let elapsed = nowMs - anchor
    let steps = max(1, (elapsed + every - 1) / every)
    anchor + steps * every
}
