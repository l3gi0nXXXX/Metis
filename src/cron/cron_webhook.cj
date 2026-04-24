package metis.cron

import magic.log.LogUtils
import magic.utils.http.HttpUtils

import std.collection.HashMap

import stdx.encoding.json.{JsonInt, JsonObject, JsonString}

/** Cron 成功/失败 webhook 投递（JSON POST）。 */
public func postCronWebhookJson(url: String, body: JsonObject, timeoutMs!: Int64 = 30_000): Bool {
    let u = url.trimAscii()
    if (u.isEmpty()) {
        return false
    }
    let headers = HashMap<String, String>()
    headers["Content-Type"] = "application/json"
    try {
        match (HttpUtils.post(u, headers, body, verify: false)) {
            case Some(_) => true
            case None =>
                LogUtils.info("CronWebhook: POST returned no response for ${u}")
                false
        }
    } catch (e: Exception) {
        LogUtils.info("CronWebhook: POST failed: ${e.message}")
        false
    }
}

public func buildCronWebhookSuccessBody(
    jobId: String,
    status: String,
    summary: String,
    runAtMs: Int64,
    sessionTarget: String
): JsonObject {
    let o = JsonObject()
    o.put("source", JsonString("metis-cron"))
    o.put("jobId", JsonString(jobId))
    o.put("status", JsonString(status))
    o.put("summary", JsonString(summary))
    o.put("runAtMs", JsonInt(runAtMs))
    o.put("sessionTarget", JsonString(sessionTarget))
    o
}

public func buildCronWebhookFailureBody(jobId: String, error: String, runAtMs: Int64, sessionTarget: String): JsonObject {
    let o = JsonObject()
    o.put("source", JsonString("metis-cron"))
    o.put("jobId", JsonString(jobId))
    o.put("status", JsonString("error"))
    o.put("error", JsonString(error))
    o.put("runAtMs", JsonInt(runAtMs))
    o.put("sessionTarget", JsonString(sessionTarget))
    o
}
