package metis.cron

/** 与参考实现的 `timer.ts` DEFAULT_BACKOFF_SCHEDULE_MS 对齐（前 5 档）。 */
private let CRON_ERROR_BACKOFF_MS: Array<Int64> =
    [30_000, 60_000, 5 * 60_000, 15 * 60_000, 60 * 60_000]

public func cronErrorBackoffMs(consecutiveErrors: Int64): Int64 {
    let n = max(1, consecutiveErrors)
    let idx = min(n - 1, CRON_ERROR_BACKOFF_MS.size - 1)
    CRON_ERROR_BACKOFF_MS[idx]
}

/** 与参考实现的 `isTransientCronError` 子集对齐（用于一次性 `at` 任务重试）。 */
public func isTransientCronError(message: String): Bool {
    let m = message.toAsciiLower()
    if (m.isEmpty()) {
        return false
    }
    if (m.contains("429") || m.contains("529")) {
        return true
    }
    if (m.contains("overloaded")) {
        return true
    }
    if (m.contains("rate") && (m.contains("limit") || m.contains("quota"))) {
        return true
    }
    if (m.contains("too many requests")) {
        return true
    }
    if (m.contains("econnreset") || m.contains("econnrefused")) {
        return true
    }
    if (m.contains("timeout") || m.contains("etimedout")) {
        return true
    }
    if (m.contains("network") || m.contains("socket") || m.contains("fetch failed")) {
        return true
    }
    false
}

/**
 * 对齐参考实现的 `computeJobNextRunAtMs`：在任务级语义下求下一触发（含 `every` 锚点回退、`at` 成功后再定档）。
 */
public func computeJobNextRun(job: CronJob, nowMs: Int64): Option<Int64> {
    if (!job.enabled) {
        return None<Int64>
    }
    let sk = job.schedule.kind.trimAscii().toAsciiLower()
    if (sk == "every") {
        var step = job.schedule.everyMs
        if (step <= 0) {
            return None<Int64>
        }
        step = max(1, step)
        let lastRun = job.state.lastRunAtMs
        if (lastRun > 0) {
            let nextFromLast = lastRun + step
            if (nextFromLast > nowMs) {
                return Some(nextFromLast)
            }
        }
        let fallbackAnchor = if (job.createdAtMs > 0) {
            job.createdAtMs
        } else {
            nowMs
        }
        let anchorResolved = if (job.schedule.anchorMs > 0) {
            job.schedule.anchorMs
        } else {
            fallbackAnchor
        }
        return Some(computeEveryNextFromAnchor(anchorResolved, step, nowMs))
    }
    if (sk == "at") {
        let atMs = job.schedule.atMs
        if (atMs <= 0) {
            return None<Int64>
        }
        let st = job.state.lastStatus.trimAscii().toAsciiLower()
        let terminalOk = st == "ok" || st == "success" || st == "skipped"
        if (terminalOk && job.state.lastRunAtMs > 0) {
            if (atMs > job.state.lastRunAtMs) {
                return Some(atMs)
            }
            return None<Int64>
        }
        return Some(atMs)
    }
    if (sk == "cron") {
        let expr = job.schedule.cronExpr.trimAscii()
        if (!expr.isEmpty() && !isValidCronFiveExpression(expr)) {
            return None<Int64>
        }
        return computeStaggeredCronNextRunAtMs(job, nowMs)
    }
    Some(nowMs + 60_000)
}
