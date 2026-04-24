package metis.gateway.runtime

import metis.gateway.core.{AgentBridge, gatewayExecuteSessionRequestTurn}
import metis.gateway.session.GatewaySessionRequest
import magic.prelude.*

import std.core.Duration
import std.time.DateTime

/** 定时任务执行超时文案。 */
public let CRON_JOB_TIMEOUT_MESSAGE: String = "cron: job execution timed out"

public func cronBridgeEpochMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toMilliseconds()
}

public func cronBridgeReply(
    bridge: AgentBridge,
    request: GatewaySessionRequest,
    prompt: String,
    timeoutMs: Int64
): String {
    if (timeoutMs <= 0) {
        return gatewayExecuteSessionRequestTurn(bridge, request, prompt).execution.answer
    }
    let deadline = cronBridgeEpochMs() + timeoutMs
    let fut = spawn {
        gatewayExecuteSessionRequestTurn(bridge, request, prompt).execution.answer
    }
    let watchdog = spawn {
        sleep(Duration.millisecond * timeoutMs)
        fut.cancel()
    }
    try {
        let out = fut.get()
        watchdog.cancel()
        return out
    } catch (e: Exception) {
        try {
            watchdog.cancel()
        } catch (_: Exception) {
            ()
        }
        if (cronBridgeEpochMs() >= deadline - 50) {
            throw Exception(CRON_JOB_TIMEOUT_MESSAGE)
        }
        throw e
    }
}
