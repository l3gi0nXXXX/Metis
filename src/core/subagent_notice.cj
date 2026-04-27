package metis.core

import magic.prelude.*

import std.collection.ArrayList
import std.fs.Path

import stdx.encoding.json.{JsonObject, JsonString}

public func gatewaySubagentNoticeTargetSession(record: JsonObject): String {
    let requester = gatewaySubagentRunRecordString(record, "requesterSessionKey")
    if (!requester.isEmpty()) {
        return requester
    }
    gatewaySubagentRunRecordString(record, "parentSessionKey")
}

public func gatewaySubagentNoticeShouldDeliver(record: JsonObject): Bool {
    let status = gatewaySubagentRunRecordString(record, "status")
    if (!gatewaySubagentRunStatusIsTerminal(status)) {
        return false
    }
    gatewaySubagentRunRecordString(record, "noticeStatus") != "delivered"
}

private func subagentNoticePreview(text: String): String {
    let trimmed = text.trimAscii()
    if (trimmed.size <= 1200) {
        return trimmed
    }
    "${trimmed[0..1200]}\n... (truncated)"
}

private func subagentNoticeLogsHint(record: JsonObject): String {
    let runId = gatewaySubagentRunRecordString(record, "runId")
    let transcriptPath = gatewaySubagentRunRecordString(record, "transcriptPath")
    if (!runId.isEmpty()) {
        return "Logs: /subagents logs ${runId}"
    }
    if (!transcriptPath.isEmpty()) {
        return "Logs: ${transcriptPath}"
    }
    "Logs: unavailable"
}

public func gatewaySubagentRenderNotice(record: JsonObject): String {
    let status = gatewaySubagentRunRecordString(record, "status")
    let runId = gatewaySubagentRunRecordString(record, "runId")
    let agentId = gatewaySubagentRunRecordString(record, "agentId")
    let summary = gatewaySubagentRunRecordString(record, "resultSummary")
    let error = gatewaySubagentRunRecordString(record, "error")
    let bodyLabel = if (status == "succeeded") { "Summary" } else { "Detail" }
    let body = if (!summary.trimAscii().isEmpty()) {
        summary
    } else if (!error.trimAscii().isEmpty()) {
        error
    } else {
        status
    }
    let lines = ArrayList<String>()
    lines.add("[Subagent ${status}] ${agentId} ${runId}")
    lines.add("Status: ${status}")
    lines.add("${bodyLabel}:")
    lines.add(subagentNoticePreview(body))
    lines.add(subagentNoticeLogsHint(record))
    String.join(lines.toArray(), delimiter: "\n")
}

public func gatewaySubagentUpdateNoticeStatus(
    sessionsRoot: Path,
    runIdOrSessionKey: String,
    noticeStatus: String,
    error!: String = ""
): Bool {
    let record = match (gatewaySubagentResolveRunRecord(sessionsRoot, runIdOrSessionKey)) {
        case Some(v) => v
        case None => return false
    }
    let normalized = match (noticeStatus.trimAscii().toAsciiLower()) {
        case "delivered" => "delivered"
        case "failed" => "failed"
        case "pending" => "pending"
        case _ => "none"
    }
    let attempts = gatewaySubagentRunRecordInt(record, "noticeAttempts")
    record.put("noticeStatus", JsonString(normalized))
    record.put("noticeAttempts", (attempts + 1).toJsonValue())
    record.put("lastNoticeError", JsonString(error.trimAscii()))
    gatewaySubagentWriteRunRecord(sessionsRoot, record)
}
