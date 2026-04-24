package metis.gateway.runtime

import std.collection.ArrayList
import stdx.encoding.json.JsonObject

/** 从 RPC / Dashboard 的 `params` 取字符串字段（与 `dashboard` 的 `rpcString` 行为一致）。 */
public func gatewayCronRpcString(params: JsonObject, key: String): String {
    match (params.get(key)) {
        case Some(v) =>
            try {
                v.asString().getValue()
            } catch (_e: Exception) {
                ""
            }
        case None => ""
    }
}

/**
 * 追加投递、重试、失败告警等 CLI flags（与 `dashboard.cron` 一致）。
 */
/** 与 `cron.add` 扩展字段一致，供 Dashboard / `cron.add` RPC 写入 CLI argv。 */
public func gatewayCronAppendOptionalJobFieldsFromParams(parts: ArrayList<String>, params: JsonObject): Unit {
    let desc = gatewayCronRpcString(params, "description").trimAscii()
    if (!desc.isEmpty()) {
        parts.add("--description")
        parts.add(desc)
    }
    let dar = gatewayCronRpcString(params, "delete_after_run").trimAscii().toAsciiLower()
    if (dar == "true" || dar == "1" || dar == "yes" || dar == "on") {
        parts.add("--delete-after-run")
    }
    let agent = gatewayCronRpcString(params, "agent_id").trimAscii()
    if (agent.isEmpty()) {
        let agent2 = gatewayCronRpcString(params, "agentId").trimAscii()
        if (!agent2.isEmpty()) {
            parts.add("--agent-id")
            parts.add(agent2)
        }
    } else {
        parts.add("--agent-id")
        parts.add(agent)
    }
    let sk = gatewayCronRpcString(params, "session_key").trimAscii()
    if (sk.isEmpty()) {
        let sk2 = gatewayCronRpcString(params, "sessionKey").trimAscii()
        if (!sk2.isEmpty()) {
            parts.add("--session-key")
            parts.add(sk2)
        }
    } else {
        parts.add("--session-key")
        parts.add(sk)
    }
    let model = gatewayCronRpcString(params, "model").trimAscii()
    if (model.isEmpty()) {
        let mo = gatewayCronRpcString(params, "model_override").trimAscii()
        if (!mo.isEmpty()) {
            parts.add("--model")
            parts.add(mo)
        }
    } else {
        parts.add("--model")
        parts.add(model)
    }
    let tl = gatewayCronRpcString(params, "thinking_level").trimAscii()
    if (!tl.isEmpty()) {
        parts.add("--thinking-level")
        parts.add(tl)
    }
    let lc = gatewayCronRpcString(params, "light_context").trimAscii().toAsciiLower()
    if (lc == "true" || lc == "1" || lc == "yes" || lc == "on") {
        parts.add("--light-context")
    }
    let daid = gatewayCronRpcString(params, "delivery_account_id").trimAscii()
    if (!daid.isEmpty()) {
        parts.add("--delivery-account-id")
        parts.add(daid)
    }
    let bed = gatewayCronRpcString(params, "best_effort_deliver").trimAscii().toAsciiLower()
    if (bed == "true" || bed == "1" || bed == "yes" || bed == "on") {
        parts.add("--best-effort-deliver")
    }
    let faid = gatewayCronRpcString(params, "failure_account_id").trimAscii()
    if (!faid.isEmpty()) {
        parts.add("--failure-account-id")
        parts.add(faid)
    }
    let faa = gatewayCronRpcString(params, "failure_alert_after").trimAscii()
    if (!faa.isEmpty()) {
        parts.add("--failure-alert-after")
        parts.add(faa)
    }
    let fac = gatewayCronRpcString(params, "failure_alert_cooldown_ms").trimAscii()
    if (!fac.isEmpty()) {
        parts.add("--failure-alert-cooldown-ms")
        parts.add(fac)
    }
}

public func gatewayCronAppendDeliveryArgs(parts: ArrayList<String>, params: JsonObject): Unit {
    let sysEv = gatewayCronRpcString(params, "system_event").trimAscii()
    let wake = gatewayCronRpcString(params, "wake_mode").trimAscii()
    let dCh = gatewayCronRpcString(params, "delivery_channel").trimAscii()
    let dTo = gatewayCronRpcString(params, "delivery_to").trimAscii()
    let ann = gatewayCronRpcString(params, "delivery_announce").trimAscii().toAsciiLower()
    let timeoutMs = gatewayCronRpcString(params, "timeout_ms").trimAscii()
    let maxRetries = gatewayCronRpcString(params, "max_retries").trimAscii()
    let retryBackoffMs = gatewayCronRpcString(params, "retry_backoff_ms").trimAscii()
    let fc = gatewayCronRpcString(params, "failure_channel").trimAscii()
    let ft = gatewayCronRpcString(params, "failure_to").trimAscii()
    let fann = gatewayCronRpcString(params, "failure_announce").trimAscii().toAsciiLower()
    if (!sysEv.isEmpty()) {
        parts.add("--system-event")
        parts.add(sysEv)
    }
    if (!wake.isEmpty()) {
        parts.add("--wake-mode")
        parts.add(wake)
    }
    if (!dCh.isEmpty()) {
        parts.add("--channel")
        parts.add(dCh)
    }
    if (!dTo.isEmpty()) {
        parts.add("--to")
        parts.add(dTo)
    }
    if (ann == "true" || ann == "1" || ann == "yes" || ann == "on") {
        parts.add("--announce")
    }
    if (!timeoutMs.isEmpty()) {
        parts.add("--timeout-ms")
        parts.add(timeoutMs)
    }
    if (!maxRetries.isEmpty()) {
        parts.add("--max-retries")
        parts.add(maxRetries)
    }
    if (!retryBackoffMs.isEmpty()) {
        parts.add("--retry-backoff-ms")
        parts.add(retryBackoffMs)
    }
    if (!fc.isEmpty()) {
        parts.add("--failure-channel")
        parts.add(fc)
    }
    if (!ft.isEmpty()) {
        parts.add("--failure-to")
        parts.add(ft)
    }
    if (fann == "true" || fann == "1" || fann == "yes" || fann == "on") {
        parts.add("--failure-announce")
    } else if (fann == "false" || fann == "0" || fann == "no" || fann == "off") {
        parts.add("--no-failure-announce")
    }
}

/**
 * `parts` 首元素须已为 `cron`。按 dashboard 的 `action` 名追加子命令与参数。
 * 成功返回 `None`；校验失败返回 `Some(错误说明)`。
 */
public func gatewayCronFillArgvForDashboardAction(
    parts: ArrayList<String>,
    action: String,
    params: JsonObject
): Option<String> {
    let act = action.trimAscii().toAsciiLower()
    if (act == "add_every") {
        let name = gatewayCronRpcString(params, "name").trimAscii()
        let every = gatewayCronRpcString(params, "every").trimAscii()
        let session = if (gatewayCronRpcString(params, "session").trimAscii().isEmpty()) {
            "main"
        } else {
            gatewayCronRpcString(params, "session").trimAscii()
        }
        let message = gatewayCronRpcString(params, "message")
        if (name.isEmpty() || every.isEmpty() || message.trimAscii().isEmpty()) {
            return Some("name, every, message required")
        }
        parts.add("add")
        parts.add("--name")
        parts.add(name)
        parts.add("--every")
        parts.add(every)
        parts.add("--session")
        parts.add(session)
        gatewayCronAppendDeliveryArgs(parts, params)
        gatewayCronAppendOptionalJobFieldsFromParams(parts, params)
        parts.add("--message")
        parts.add(message)
        return None
    }
    if (act == "add_at") {
        let name = gatewayCronRpcString(params, "name").trimAscii()
        let atRaw = gatewayCronRpcString(params, "at").trimAscii()
        let session = if (gatewayCronRpcString(params, "session").trimAscii().isEmpty()) {
            "main"
        } else {
            gatewayCronRpcString(params, "session").trimAscii()
        }
        let message = gatewayCronRpcString(params, "message")
        if (name.isEmpty() || atRaw.isEmpty() || message.trimAscii().isEmpty()) {
            return Some("name, at, message required")
        }
        parts.add("add")
        parts.add("--name")
        parts.add(name)
        parts.add("--at")
        parts.add(atRaw)
        parts.add("--session")
        parts.add(session)
        gatewayCronAppendDeliveryArgs(parts, params)
        gatewayCronAppendOptionalJobFieldsFromParams(parts, params)
        parts.add("--message")
        parts.add(message)
        return None
    }
    if (act == "add_cron") {
        let name = gatewayCronRpcString(params, "name").trimAscii()
        let cronExpr = gatewayCronRpcString(params, "cron_expr").trimAscii()
        let tz = if (gatewayCronRpcString(params, "time_zone").trimAscii().isEmpty()) {
            "UTC"
        } else {
            gatewayCronRpcString(params, "time_zone").trimAscii()
        }
        let session = if (gatewayCronRpcString(params, "session").trimAscii().isEmpty()) {
            "main"
        } else {
            gatewayCronRpcString(params, "session").trimAscii()
        }
        let message = gatewayCronRpcString(params, "message")
        if (name.isEmpty() || cronExpr.isEmpty() || message.trimAscii().isEmpty()) {
            return Some("name, cron_expr, message required")
        }
        parts.add("add")
        parts.add("--name")
        parts.add(name)
        parts.add("--cron")
        parts.add(cronExpr)
        parts.add("--tz")
        parts.add(tz)
        parts.add("--session")
        parts.add(session)
        gatewayCronAppendDeliveryArgs(parts, params)
        gatewayCronAppendOptionalJobFieldsFromParams(parts, params)
        parts.add("--message")
        parts.add(message)
        return None
    }
    if (act == "remove" || act == "enable" || act == "disable") {
        let id = gatewayCronRpcString(params, "id").trimAscii()
        if (id.isEmpty()) {
            return Some("id is empty")
        }
        parts.add(act)
        parts.add(id)
        return None
    }
    if (act == "status" || act == "path" || act == "help" || act == "list") {
        parts.add(act)
        return None
    }
    if (act == "update") {
        let targetId = if (gatewayCronRpcString(params, "jobId").trimAscii().isEmpty()) {
            gatewayCronRpcString(params, "id").trimAscii()
        } else {
            gatewayCronRpcString(params, "jobId").trimAscii()
        }
        if (targetId.isEmpty()) {
            return Some("jobId is empty")
        }
        parts.add("update")
        parts.add("--job-id")
        parts.add(targetId)
        let en = gatewayCronRpcString(params, "enabled").trimAscii().toAsciiLower()
        let msg = gatewayCronRpcString(params, "message")
        if (!en.isEmpty()) {
            parts.add("--enabled")
            parts.add(en)
        }
        if (!msg.trimAscii().isEmpty()) {
            parts.add("--message")
            parts.add(msg)
        }
        gatewayCronAppendDeliveryArgs(parts, params)
        gatewayCronAppendOptionalJobFieldsFromParams(parts, params)
        return None
    }
    if (act == "run") {
        let targetId = if (gatewayCronRpcString(params, "jobId").trimAscii().isEmpty()) {
            gatewayCronRpcString(params, "id").trimAscii()
        } else {
            gatewayCronRpcString(params, "jobId").trimAscii()
        }
        if (targetId.isEmpty()) {
            return Some("jobId is empty")
        }
        parts.add("run")
        parts.add("--job-id")
        parts.add(targetId)
        let dueStr = gatewayCronRpcString(params, "due_only").trimAscii().toAsciiLower()
        if (dueStr == "true" || dueStr == "1" || dueStr == "yes") {
            parts.add("--due")
        }
        return None
    }
    if (act == "runs") {
        parts.add("runs")
        let targetId = if (gatewayCronRpcString(params, "jobId").trimAscii().isEmpty()) {
            gatewayCronRpcString(params, "id").trimAscii()
        } else {
            gatewayCronRpcString(params, "jobId").trimAscii()
        }
        if (!targetId.isEmpty()) {
            parts.add("--job-id")
            parts.add(targetId)
        }
        return None
    }
    if (act == "wake") {
        parts.add("wake")
        let targetId = if (gatewayCronRpcString(params, "jobId").trimAscii().isEmpty()) {
            gatewayCronRpcString(params, "id").trimAscii()
        } else {
            gatewayCronRpcString(params, "jobId").trimAscii()
        }
        if (!targetId.isEmpty()) {
            parts.add("--job-id")
            parts.add(targetId)
        }
        let wakeMode = gatewayCronRpcString(params, "mode").trimAscii()
        if (!wakeMode.isEmpty()) {
            parts.add("--mode")
            parts.add(wakeMode)
        }
        let wakeText = gatewayCronRpcString(params, "text").trimAscii()
        if (!wakeText.isEmpty()) {
            parts.add("--text")
            parts.add(wakeText)
        }
        return None
    }
    if (act == "edit_message") {
        let id = gatewayCronRpcString(params, "id").trimAscii()
        let message = gatewayCronRpcString(params, "message")
        if (id.isEmpty() || message.trimAscii().isEmpty()) {
            return Some("id or message empty")
        }
        parts.add("edit")
        parts.add(id)
        parts.add("--message")
        parts.add(message)
        return None
    }
    if (act == "edit_enabled") {
        let id = gatewayCronRpcString(params, "id").trimAscii()
        let enabled = gatewayCronRpcString(params, "enabled").trimAscii().toAsciiLower()
        if (id.isEmpty() || (enabled != "true" && enabled != "false")) {
            return Some("id or enabled invalid")
        }
        parts.add("edit")
        parts.add(id)
        parts.add("--enabled")
        parts.add(enabled)
        return None
    }
    Some("unknown action")
}

/** 推断 `cron.add` 使用的子类型：显式 `action` 或按 `cron_expr` / `at` / `every` 字段。 */
public func gatewayCronInferAddAction(params: JsonObject): Option<String> {
    let actRaw = gatewayCronRpcString(params, "action").trimAscii().toAsciiLower()
    if (actRaw == "add_every" || actRaw == "add_at" || actRaw == "add_cron") {
        return Some(actRaw)
    }
    let ce = gatewayCronRpcString(params, "cron_expr").trimAscii()
    let at = gatewayCronRpcString(params, "at").trimAscii()
    let ev = gatewayCronRpcString(params, "every").trimAscii()
    if (!ce.isEmpty()) {
        return Some("add_cron")
    }
    if (!at.isEmpty()) {
        return Some("add_at")
    }
    if (!ev.isEmpty()) {
        return Some("add_every")
    }
    None
}
