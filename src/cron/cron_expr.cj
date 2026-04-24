package metis.cron

import std.collection.{ArrayList, HashSet}
import std.convert.Parsable

/**
 * 五段式 cron（分 时 日 月 周）在固定时区偏移下的「下一触发」计算。
 * 支持：星号通配、单值、区间、逗号列表、以及「星号 + 斜杠 + 步长」与「区间 + 斜杠 + 步长」写法。
 * 即 `*`、单值、`a-b`、列表 `a,b,c`、`星号/n`、`a-b/n`。
 * 日/周：若两者均非「全量」，按 Vixie cron 语义为 **或**；否则由非全量字段决定。
 *
 * 时区：`UTC`/`GMT`/空 → 0；`Local` → 0（与进程一致由部署保证）；`±HH` 或 `±HH:MM` 固定偏移。
 */

/** 解析 `--tz`：相对 UTC 的分钟偏移 */
public func parseCronTimeZoneOffsetMinutes(raw: String): Option<Int64> {
    let t = raw.trimAscii()
    if (t.isEmpty() || t.toAsciiLower() == "utc" || t.toAsciiUpper() == "GMT") {
        return Some(0)
    }
    if (t.toAsciiLower() == "local") {
        return Some(0)
    }
    var s = t
    var sign: Int64 = 1
    if (s.size > 0 && s[0..1] == "-") {
        sign = -1
        s = s[1..].trimAscii()
    } else if (s.size > 0 && s[0..1] == "+") {
        s = s[1..].trimAscii()
    }
    if (s.isEmpty()) {
        return None<Int64>
    }
    if (s.indexOf(":").isNone()) {
        try {
            let h = Int64.parse(s)
            return Some(sign * h * 60)
        } catch (_: Exception) {
            return None<Int64>
        }
    }
    let colon = s.indexOf(":").getOrThrow()
    if (colon <= 0 || colon >= s.size - 1) {
        return None<Int64>
    }
    try {
        let h = Int64.parse(s[0..colon].trimAscii())
        let mi = Int64.parse(s[colon + 1..].trimAscii())
        if (mi < 0 || mi >= 60) {
            return None<Int64>
        }
        Some(sign * (h * 60 + mi))
    } catch (_: Exception) {
        None<Int64>
    }
}

private func isLeapYear(y: Int64): Bool {
    (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0)
}

private func daysInMonth(y: Int64, m: Int64): Int64 {
    if (m == 2) {
        return if (isLeapYear(y)) {
            29
        } else {
            28
        }
    }
    if (m == 4 || m == 6 || m == 9 || m == 11) {
        return 30
    }
    31
}

/** synthetic ms：与 UTC 毫秒时间轴平行，表示 (UTC + offset) 的展示轴，用于拆日历 */
private func splitSyntheticWall(synMs: Int64): (Int64, Int64, Int64, Int64, Int64) {
    var days = synMs / 86400000
    if (synMs < 0 && synMs % 86400000 != 0) {
        days -= 1
    }
    var rem = synMs - days * 86400000
    if (rem < 0) {
        rem += 86400000
        days -= 1
    }
    let hod = rem / 3600000
    let rem2 = rem % 3600000
    let minute = rem2 / 60000
    var y: Int64 = 1970
    var dLeft = days
    while (true) {
        let diy = if (isLeapYear(y)) {
            366
        } else {
            365
        }
        if (dLeft < diy) {
            break
        }
        dLeft -= diy
        y += 1
    }
    var mon: Int64 = 1
    while (mon <= 12) {
        let dim = daysInMonth(y, mon)
        if (dLeft < dim) {
            let dom = dLeft + 1
            return (y, mon, dom, hod, minute)
        }
        dLeft -= dim
        mon += 1
    }
    (y, 12, 31, 23, 59)
}

private func dowSun0(y: Int64, m: Int64, d: Int64): Int64 {
    var mm = m
    var yy = y
    if (mm < 3) {
        mm += 12
        yy -= 1
    }
    let q = d
    let k = yy % 100
    let j = yy / 100
    var h = (q + (13 * (mm + 1)) / 5 + k + k / 4 + j / 4 - 2 * j) % 7
    h = (h + 7) % 7
    let sat0 = (h + 6) % 7
    (sat0 + 1) % 7
}

/** 单段 cron 字段（闭区间 min..max） */
private class CronField {
    /** true 表示 *，匹配任意 */
    CronField(public let wildcard: Bool, public let values: HashSet<Int64>) {}

    func allows(v: Int64): Bool {
        if (this.wildcard) {
            return true
        }
        return this.values.contains(v)
    }
}

private func addValue(st: HashSet<Int64>, minV: Int64, maxV: Int64, v: Int64): Bool {
    if (v < minV || v > maxV) {
        return false
    }
    st.add(v)
    true
}

private func fillRange(st: HashSet<Int64>, minV: Int64, maxV: Int64, lo: Int64, hi: Int64, step: Int64): Bool {
    if (step <= 0 || lo > hi) {
        return false
    }
    var x = lo
    while (x <= hi) {
        if (!addValue(st, minV, maxV, x)) {
            return false
        }
        x += step
    }
    true
}

/** 解析一段（已去掉 step 后缀的 core 与 step 正整数） */
private func steppedStarSet(minV: Int64, maxV: Int64, step: Int64): Option<HashSet<Int64>> {
    let st = HashSet<Int64>()
    if (!fillRange(st, minV, maxV, minV, maxV, step)) {
        return None<HashSet<Int64>>
    }
    Some(st)
}

private func parseFieldCore(minV: Int64, maxV: Int64, core: String, step: Int64): Option<CronField> {
    let c = core.trimAscii()
    if (c.isEmpty()) {
        return None<CronField>
    }
    if (c == "*") {
        if (step == 1) {
            return Some(CronField(true, HashSet<Int64>()))
        }
        match (steppedStarSet(minV, maxV, step)) {
            case Some(st) => return Some(CronField(false, st))
            case None => return None<CronField>
        }
    }
    let st = HashSet<Int64>()
    for (segRaw in c.split(",")) {
        let seg = segRaw.trimAscii()
        if (seg.isEmpty()) {
            continue
        }
        if (seg.indexOf("-").isSome()) {
            let ih = seg.indexOf("-").getOrThrow()
            if (ih <= 0 || ih >= seg.size - 1) {
                return None<CronField>
            }
            try {
                let a = Int64.parse(seg[0..ih].trimAscii())
                let b = Int64.parse(seg[ih + 1..].trimAscii())
                let lo = if (a <= b) {
                    a
                } else {
                    b
                }
                let hi = if (a <= b) {
                    b
                } else {
                    a
                }
                if (!fillRange(st, minV, maxV, lo, hi, step)) {
                    return None<CronField>
                }
            } catch (_: Exception) {
                return None<CronField>
            }
            continue
        }
        try {
            let v = Int64.parse(seg)
            if (step != 1) {
                return None<CronField>
            }
            if (!addValue(st, minV, maxV, v)) {
                return None<CronField>
            }
        } catch (_: Exception) {
            return None<CronField>
        }
    }
    Some(CronField(false, st))
}

private func parseFieldPart(minV: Int64, maxV: Int64, part: String): Option<CronField> {
    let p = part.trimAscii()
    if (p.isEmpty()) {
        return None<CronField>
    }
    if (p.indexOf("/").isSome()) {
        let ix = p.indexOf("/").getOrThrow()
        if (ix <= 0 || ix >= p.size - 1) {
            return None<CronField>
        }
        let core = p[0..ix].trimAscii()
        try {
            let step = Int64.parse(p[ix + 1..].trimAscii())
            if (step <= 0) {
                return None<CronField>
            }
            return parseFieldCore(minV, maxV, core, step)
        } catch (_: Exception) {
            return None<CronField>
        }
    } else {
        return parseFieldCore(minV, maxV, p, 1)
    }
}

private func parseFiveFields(expr: String): Option<(CronField, CronField, CronField, CronField, CronField)> {
    let t = expr.trimAscii()
    let parts = ArrayList<String>()
    for (seg in t.split(" ")) {
        let one = seg.trimAscii()
        if (!one.isEmpty()) {
            parts.add(one)
        }
    }
    if (parts.size != 5) {
        return None<(CronField, CronField, CronField, CronField, CronField)>
    }
    let mOpt = parseFieldPart(0, 59, parts[0])
    let hOpt = parseFieldPart(0, 23, parts[1])
    let domOpt = parseFieldPart(1, 31, parts[2])
    let monOpt = parseFieldPart(1, 12, parts[3])
    let dowOpt = parseFieldPart(0, 7, parts[4])
    if (let Some(m) <- mOpt) {
        if (let Some(h) <- hOpt) {
            if (let Some(dom) <- domOpt) {
                if (let Some(mon) <- monOpt) {
                    if (let Some(dow) <- dowOpt) {
                        return Some((m, h, dom, mon, dow))
                    }
                }
            }
        }
    }
    None<(CronField, CronField, CronField, CronField, CronField)>
}

private func dowAllows(f: CronField, dow: Int64): Bool {
    if (f.wildcard) {
        return true
    }
    f.values.contains(dow) || (dow == 0 && f.values.contains(7))
}

private func domAllows(f: CronField, dom: Int64): Bool {
    f.allows(dom)
}

private func monthAllows(f: CronField, mon: Int64): Bool {
    f.allows(mon)
}

/** Vixie：日、周都限制时，满足 dom 或 dow 之一即可 */
private func dayMatches(domF: CronField, dowF: CronField, dom: Int64, dow: Int64): Bool {
    let domAll = domF.wildcard
    let dowAll = dowF.wildcard
    if (domAll && dowAll) {
        return true
    }
    if (domAll) {
        return dowAllows(dowF, dow)
    }
    if (dowAll) {
        return domAllows(domF, dom)
    }
    domAllows(domF, dom) || dowAllows(dowF, dow)
}

private func cronMatches(
    minuteF: CronField,
    hourF: CronField,
    domF: CronField,
    monF: CronField,
    dowF: CronField,
    minute: Int64,
    hour: Int64,
    dom: Int64,
    mon: Int64,
    dow: Int64
): Bool {
    if (!minuteF.allows(minute) || !hourF.allows(hour)) {
        return false
    }
    if (!monthAllows(monF, mon)) {
        return false
    }
    dayMatches(domF, dowF, dom, dow)
}

/** 下一触发 Unix 毫秒；`lastRunAtMs` 用于避免同一分钟内重复 */
public func computeNextCronRunUtcMs(expr: String, offsetMin: Int64, fromUtcMs: Int64, lastRunAtMs: Int64): Option<Int64> {
    match (parseFiveFields(expr)) {
        case None => None<Int64>
        case Some((minuteF, hourF, domF, monF, dowF)) =>
            var start = fromUtcMs
            if (lastRunAtMs > 0 && start <= lastRunAtMs) {
                start = lastRunAtMs + 1
            }
            let offMs = offsetMin * 60000
            var local = start + offMs
            var n = (local + 59999) / 60000
            var k: Int64 = 0
            while (k < 527040) {
                let localMinuteStart = n * 60000
                let utcCandidate = localMinuteStart - offMs
                let (yy, mm, dd, hh, mi) = splitSyntheticWall(localMinuteStart)
                let dow = dowSun0(yy, mm, dd)
                if (utcCandidate >= start && cronMatches(minuteF, hourF, domF, monF, dowF, mi, hh, dd, mm, dow)) {
                    return Some(utcCandidate)
                }
                n += 1
                k += 1
            }
            None<Int64>
    }
}

public func isValidCronFiveExpression(expr: String): Bool {
    parseFiveFields(expr).isSome()
}
