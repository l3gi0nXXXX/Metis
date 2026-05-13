package metis.cliapp

import magic.log.LogUtils

import metis.gateway.runtime.{gatewayCliClient, gatewayEnsureSubagentNoticeEventPublisherRegistered}
import metis.io.PrintUtils
import metis.program_support.{
    programSupportCliSubagentNoticeEventMatchesSession,
    programSupportCliSubagentNoticeFromGatewayEvent,
    programSupportCliSubagentNoticeGatewayEventSessionKey,
    programSupportCliSubagentNoticesFromGatewayStreamResult
}

import std.sync.AtomicBool
import stdx.encoding.json.{JsonObject, JsonValue}

private let CLI_SUBAGENT_NOTICE_EVENT_KIND = "session.subagent.notice"

public func cliSubagentNoticeFromGatewayEvent(event: JsonObject): Option<String> {
    programSupportCliSubagentNoticeFromGatewayEvent(event)
}

public func cliSubagentNoticeGatewayEventSessionKey(event: JsonObject): String {
    programSupportCliSubagentNoticeGatewayEventSessionKey(event)
}

public func cliSubagentNoticeEventMatchesSession(event: JsonObject, sessionKey: String): Bool {
    programSupportCliSubagentNoticeEventMatchesSession(event, sessionKey)
}

public func cliSubagentNoticesFromGatewayStreamResult(result: JsonValue, sessionKey: String): Array<String> {
    programSupportCliSubagentNoticesFromGatewayStreamResult(result, sessionKey)
}

protected class CliSubagentNoticeWatcher {
    private let sessionKey: String
    private let stopRequested = AtomicBool(false)
    private var future: Option<Future<Unit>> = None

    init(sessionKey: String) {
        this.sessionKey = sessionKey.trimAscii()
        gatewayEnsureSubagentNoticeEventPublisherRegistered()
    }

    func start(): Unit {
        if (this.future.isSome()) {
            return
        }
        this.future = spawn {
            while (!this.stopRequested.load() && !Thread.currentThread.hasPendingCancellation) {
                this.pollOnce()
                sleep(Duration.millisecond * 700)
            }
        }
    }

    func stop(): Unit {
        this.stopRequested.store(true)
        if (let Some(f) <- this.future) {
            f.cancel()
        }
    }

    private func pollOnce(): Unit {
        try {
            let response = gatewayCliClient().streamEvents(
                limit: 8,
                waitMs: 700,
                eventKinds: [CLI_SUBAGENT_NOTICE_EVENT_KIND]
            )
            if (!response.ok) {
                LogUtils.debug("CLI subagent notice gateway stream failed: ${response.error}")
                return
            }
            let notices = cliSubagentNoticesFromGatewayStreamResult(response.result, this.sessionKey)
            for (notice in notices) {
                this.printNotice(notice)
            }
        } catch (e: Exception) {
            LogUtils.debug("CLI subagent notice gateway stream poll failed: ${e.message}")
        }
    }

    private func printNotice(notice: String): Unit {
        PrintUtils.printLine("")
        PrintUtils.printLine(PrintUtils.renderAssistantResponseBox(notice))
        PrintUtils.printLine("")
    }
}

protected func startCliSubagentNoticeWatcher(): CliSubagentNoticeWatcher {
    let watcher = CliSubagentNoticeWatcher("main")
    watcher.start()
    watcher
}
