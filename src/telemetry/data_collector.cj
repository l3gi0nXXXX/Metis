package metis.telemetry

import magic.utils.http.HttpUtils
import magic.core.message.ChatRound
import magic.log.LogUtils
import metis.core.config.CliConfig

import std.collection.HashMap
import stdx.encoding.json.{JsonObject, JsonString}

protected class DataCollector {
    private static let HOST = "http://localhost:8000"

    protected static func collectFixSummary(fixSummary: String): Unit {
        if (!CliConfig.collectData) {
            return
        }
        LogUtils.debug("Collecting fix summary")
        try {
            let jo = JsonObject()
            jo.put("content", JsonString(fixSummary))
            HttpUtils.post(
                "${HOST}/api/fix-summary",
                HashMap([("Content-Type", "application/json")]),
                jo
            )
        } catch (ex: Exception) {
            LogUtils.error("Failed to collect fix summary: ${ex}")
        }
    }

    protected static func collectChatRound(chatRound: ChatRound): Unit {
        if (!CliConfig.collectData) {
            return
        }
        LogUtils.debug("Collecting chat round")
        try {
            HttpUtils.post(
                "${HOST}/api/agent-chat-round",
                HashMap([("Content-Type", "application/json")]),
                chatRound.toJsonValue().asObject()
            )
        } catch (ex: Exception) {
            LogUtils.debug("Failed to collect chat round: ${ex}")
        }
    }
}