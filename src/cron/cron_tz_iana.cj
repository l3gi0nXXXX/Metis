package metis.cron

import std.collection.HashMap

private var ianaCronOffsetCache: Option<HashMap<String, Int64>> = None<HashMap<String, Int64>>

private func ianaCronOffsetMinutesTable(): HashMap<String, Int64> {
    match (ianaCronOffsetCache) {
        case Some(m) => return m
        case None => ()
    }
    let m = HashMap<String, Int64>()
    m["utc"] = 0
    m["gmt"] = 0
    m["etc/utc"] = 0
    m["etc/gmt"] = 0
    m["asia/shanghai"] = 8 * 60
    m["asia/chongqing"] = 8 * 60
    m["asia/hong_kong"] = 8 * 60
    m["asia/taipei"] = 8 * 60
    m["asia/singapore"] = 8 * 60
    m["asia/tokyo"] = 9 * 60
    m["asia/seoul"] = 9 * 60
    m["asia/kolkata"] = 5 * 60 + 30
    m["asia/dubai"] = 4 * 60
    m["europe/london"] = 0
    m["europe/paris"] = 1 * 60
    m["europe/berlin"] = 1 * 60
    m["america/new_york"] = -5 * 60
    m["america/chicago"] = -6 * 60
    m["america/denver"] = -7 * 60
    m["america/los_angeles"] = -8 * 60
    m["australia/sydney"] = 10 * 60
    m["pacific/auckland"] = 12 * 60
    ianaCronOffsetCache = Some(m)
    m
}

/** 若识别为表内 IANA，返回固定偏移分钟；否则 `None`。 */
public func tryIanaTimeZoneOffsetMinutes(raw: String): Option<Int64> {
    let k = raw.trimAscii().toAsciiLower()
    if (k.isEmpty()) {
        return None<Int64>
    }
    match (ianaCronOffsetMinutesTable().get(k)) {
        case Some(v) => Some(v)
        case None => None<Int64>
    }
}

/**
 * 解析 `--tz`：先尝试 `parseCronTimeZoneOffsetMinutes`（UTC/Local/±HH），再尝试常见 IANA 表。
 * 无法识别时返回 `None`（调用方可拒绝或回退 0）。
 */
public func cronResolveTimeZoneOffsetMinutes(raw: String): Option<Int64> {
    let t = raw.trimAscii()
    if (t.isEmpty()) {
        return Some(0)
    }
    match (parseCronTimeZoneOffsetMinutes(t)) {
        case Some(m) => Some(m)
        case None => tryIanaTimeZoneOffsetMinutes(t)
    }
}

/** 调度计算用：无法解析时回退 0（UTC）。 */
public func cronTimeZoneOffsetMinutesForSchedule(raw: String): Int64 {
    match (cronResolveTimeZoneOffsetMinutes(raw)) {
        case Some(m) => m
        case None => 0
    }
}
