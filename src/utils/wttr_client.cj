package metis.utils

import magic.log.LogUtils
import magic.utils.http.HttpUtils

import std.collection.HashMap

private const WTTR_HOST = "https://wttr.in"
private const MAX_LOCATION_LEN: Int64 = 128

/**
 * 通过 HTTP 请求 wttr.in 纯文本（不依赖本机 curl）。
 * 放在 `metis.utils`，避免 `metis.gateway.tools` → `metis.core.tools` 与 `gateway_sessions_toolset` → `gateway.core` 形成环依赖。
 */
public func fetchWttrWeatherPlain(location: String): String {
    let url = try {
        buildWttrUrl(location)
    } catch (e: Exception) {
        return "天气查询参数无效：${e.message}"
    }
    let headers = HashMap<String, String>([
        ("User-Agent", "Metis-Weather/1.0"),
        ("Accept", "text/plain,*/*")
    ])
    try {
        let opt = HttpUtils.get(url, headers, None, verify: false)
        let body = match (opt) {
            case Some(s) => s
            case None => return "天气服务无响应（HTTP 空）"
        }
        let t = body.trimAscii()
        if (t.size > 12000) {
            return t[0..12000] + "\n…(已截断)"
        }
        return t
    } catch (e: Exception) {
        LogUtils.info("Weather HTTP failed: ${e.message}")
        return "天气查询失败：${e.message}"
    }
}

private func buildWttrUrl(location: String): String {
    let raw = location.trimAscii()
    if (raw.isEmpty()) {
        return "${WTTR_HOST}/?format=3"
    }
    if (raw.size > MAX_LOCATION_LEN) {
        throw Exception("地点过长")
    }
    for (bad in ["\n", "\r", "\t", "://", "..", "?", "#", "\\", "%00"]) {
        if (raw.contains(bad)) {
            throw Exception("地点含有非法字符")
        }
    }
    let path = raw.replace(" ", "+")
    return "${WTTR_HOST}/${path}?format=3"
}
