package metis.gateway.runtime

import magic.jsonable.*

import std.collection.ArrayList
import stdx.encoding.json.{JsonObject, JsonString, JsonValue}

private func gatewayCronRpcResultResponse(method: String, output: String, exitCode: Int64): GatewayRpcResponse {
    let result = JsonObject()
    result.put("output", JsonString(output))
    result.put("exitCode", exitCode.toJsonValue())
    GatewayRpcResponse(
        exitCode == 0,
        method,
        result: result,
        error: if (exitCode == 0) {
            ""
        } else {
            output
        }
    )
}

/**
 * 顶层 `cron.*` RPC，与 `gateway cron` / `gatewayExecuteCronWithUnifiedRun` 同源。
 *
 * - `cron.list` / `cron.path`：只读
 * - `cron.add`：参数与 `dashboard.cron` 的 add 一致，可按字段推断 `add_every` / `add_at` / `add_cron`，或显传 `action`
 * - `cron.update`：同 dashboard `update`
 * - `cron.run`：`job_id` 或 `id`，可选 `due_only`
 * - `cron.remove` / `cron.enable` / `cron.disable`：参数 `id`
 * - `cron.runs` / `cron.wake`：与 CLI 一致
 */
public func handleGatewayCronFamily(method: String, request: GatewayRpcRequest): Option<GatewayRpcResponse> {
    let m = method.trimAscii().toAsciiLower()
    let p = request.params

    if (m == "cron.list") {
        let pair = gatewayExecuteCronWithUnifiedRun(["cron", "list"])
        return Some(gatewayCronRpcResultResponse(method, pair[0], pair[1]))
    }
    if (m == "cron.path") {
        let pair = gatewayExecuteCronWithUnifiedRun(["cron", "path"])
        return Some(gatewayCronRpcResultResponse(method, pair[0], pair[1]))
    }
    if (m == "cron.help") {
        let pair = gatewayExecuteCronWithUnifiedRun(["cron", "help"])
        return Some(gatewayCronRpcResultResponse(method, pair[0], pair[1]))
    }
    if (m == "cron.status") {
        let pair = gatewayExecuteCronWithUnifiedRun(["cron", "status"])
        return Some(gatewayCronRpcResultResponse(method, pair[0], pair[1]))
    }

    if (m == "cron.add") {
        match (gatewayCronInferAddAction(p)) {
            case None =>
                return Some(
                    GatewayRpcResponse(
                        false,
                        method,
                        error: "cannot infer schedule: set every, at, or cron_expr (or action=add_every|add_at|add_cron)"
                    )
                )
            case Some(subAct) =>
                let parts = ArrayList<String>()
                parts.add("cron")
                match (gatewayCronFillArgvForDashboardAction(parts, subAct, p)) {
                    case Some(err) => return Some(GatewayRpcResponse(false, method, error: err))
                    case None => ()
                }
                let pair = gatewayExecuteCronWithUnifiedRun(parts.toArray())
                return Some(gatewayCronRpcResultResponse(method, pair[0], pair[1]))
        }
    }

    if (m == "cron.update") {
        let parts = ArrayList<String>()
        parts.add("cron")
        match (gatewayCronFillArgvForDashboardAction(parts, "update", p)) {
            case Some(err) => return Some(GatewayRpcResponse(false, method, error: err))
            case None => ()
        }
        let pair = gatewayExecuteCronWithUnifiedRun(parts.toArray())
        return Some(gatewayCronRpcResultResponse(method, pair[0], pair[1]))
    }

    if (m == "cron.run") {
        let parts = ArrayList<String>()
        parts.add("cron")
        match (gatewayCronFillArgvForDashboardAction(parts, "run", p)) {
            case Some(err) => return Some(GatewayRpcResponse(false, method, error: err))
            case None => ()
        }
        let pair = gatewayExecuteCronWithUnifiedRun(parts.toArray())
        return Some(gatewayCronRpcResultResponse(method, pair[0], pair[1]))
    }

    if (m == "cron.remove") {
        let parts = ArrayList<String>()
        parts.add("cron")
        match (gatewayCronFillArgvForDashboardAction(parts, "remove", p)) {
            case Some(err) => return Some(GatewayRpcResponse(false, method, error: err))
            case None => ()
        }
        let pair = gatewayExecuteCronWithUnifiedRun(parts.toArray())
        return Some(gatewayCronRpcResultResponse(method, pair[0], pair[1]))
    }
    if (m == "cron.enable") {
        let parts = ArrayList<String>()
        parts.add("cron")
        match (gatewayCronFillArgvForDashboardAction(parts, "enable", p)) {
            case Some(err) => return Some(GatewayRpcResponse(false, method, error: err))
            case None => ()
        }
        let pair = gatewayExecuteCronWithUnifiedRun(parts.toArray())
        return Some(gatewayCronRpcResultResponse(method, pair[0], pair[1]))
    }
    if (m == "cron.disable") {
        let parts = ArrayList<String>()
        parts.add("cron")
        match (gatewayCronFillArgvForDashboardAction(parts, "disable", p)) {
            case Some(err) => return Some(GatewayRpcResponse(false, method, error: err))
            case None => ()
        }
        let pair = gatewayExecuteCronWithUnifiedRun(parts.toArray())
        return Some(gatewayCronRpcResultResponse(method, pair[0], pair[1]))
    }

    if (m == "cron.runs") {
        let parts = ArrayList<String>()
        parts.add("cron")
        match (gatewayCronFillArgvForDashboardAction(parts, "runs", p)) {
            case Some(err) => return Some(GatewayRpcResponse(false, method, error: err))
            case None => ()
        }
        let pair = gatewayExecuteCronWithUnifiedRun(parts.toArray())
        return Some(gatewayCronRpcResultResponse(method, pair[0], pair[1]))
    }
    if (m == "cron.wake") {
        let parts = ArrayList<String>()
        parts.add("cron")
        match (gatewayCronFillArgvForDashboardAction(parts, "wake", p)) {
            case Some(err) => return Some(GatewayRpcResponse(false, method, error: err))
            case None => ()
        }
        let pair = gatewayExecuteCronWithUnifiedRun(parts.toArray())
        return Some(gatewayCronRpcResultResponse(method, pair[0], pair[1]))
    }

    None
}
