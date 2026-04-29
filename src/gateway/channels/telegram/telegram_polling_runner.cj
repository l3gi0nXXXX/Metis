package metis.gateway.channels.telegram

import magic.jsonable.*

import std.sync.Mutex
import std.time.*
import stdx.encoding.json.*

public class TelegramPollingRunner {
    private let fetchUpdates: () -> String
    private let ingestUpdates: (String) -> Int64
    private let shouldContinue: () -> Bool
    private let rebuildTransport: () -> Unit
    private let stateLock = Mutex()
    private var running: Bool = false
    private var watchdogRunning: Bool = false
    private var pollingState: String = "idle"
    private var lastError: String = ""
    private var lastErrorAtMs: Int64 = 0
    private var lastSuccessAtMs: Int64 = 0
    private var lastStartedAtMs: Int64 = 0
    private var lastFinishedAtMs: Int64 = 0
    private var consecutiveFailures: Int64 = 0
    private var nextRetryAtMs: Int64 = 0
    private var lastOutcome: String = "idle"
    private var lastStallReason: String = ""
    private var lastStallAtMs: Int64 = 0
    private var watchdogRestartCount: Int64 = 0
    private var transportRebuildCount: Int64 = 0
    private var watchdogStallMs: Int64 = 45000
    private var watchdogIntervalMs: Int64 = 500
    private var loopGeneration: Int64 = 0

    public init(
        fetchUpdates: () -> String,
        ingestUpdates: (String) -> Int64,
        shouldContinue: () -> Bool,
        rebuildTransport!: () -> Unit = { => () },
        watchdogStallMs!: Int64 = 45000,
        watchdogIntervalMs!: Int64 = 500
    ) {
        this.fetchUpdates = fetchUpdates
        this.ingestUpdates = ingestUpdates
        this.shouldContinue = shouldContinue
        this.rebuildTransport = rebuildTransport
        this.watchdogStallMs = if (watchdogStallMs > 0) { watchdogStallMs } else { 45000 }
        this.watchdogIntervalMs = if (watchdogIntervalMs > 0) { watchdogIntervalMs } else { 500 }
    }

    public func start(): Unit {
        synchronized(this.stateLock) {
            if (this.running) {
                return
            }
            this.running = true
            this.pollingState = "idle"
            this.lastOutcome = "idle"
            this.nextRetryAtMs = 0
            this.loopGeneration += 1
        }
        let generation = this.currentLoopGeneration()
        spawn {
            this.runLoop(generation)
        }
        this.startWatchdog()
    }

    public func stop(): Unit {
        synchronized(this.stateLock) {
            this.running = false
            this.watchdogRunning = false
            this.pollingState = "stopped"
            this.lastOutcome = "stopped"
            this.nextRetryAtMs = 0
        }
    }

    public func markIdle(): Unit {
        synchronized(this.stateLock) {
            this.pollingState = "idle"
            this.lastOutcome = "idle"
            this.nextRetryAtMs = 0
        }
    }

    public func runIteration(): Int64 {
        this.markStarted()
        try {
            let raw = this.fetchUpdates()
            if (!raw.trimAscii().isEmpty()) {
                return this.ingestUpdates(raw)
            }
        } catch (e: Exception) {
            this.recordError("polling iteration exception: ${e.message}", outcome: "exception")
        }
        0
    }

    public func recordSuccess(outcome!: String = "success"): Unit {
        let now = this.nowMs()
        synchronized(this.stateLock) {
            this.pollingState = "polling"
            this.lastSuccessAtMs = now
            this.lastFinishedAtMs = now
            this.consecutiveFailures = 0
            this.nextRetryAtMs = 0
            this.lastOutcome = outcome
        }
    }

    public func recordError(error: String, outcome!: String = "error"): Unit {
        let now = this.nowMs()
        synchronized(this.stateLock) {
            this.pollingState = "recovering"
            this.lastError = error.trimAscii()
            this.lastErrorAtMs = now
            this.lastFinishedAtMs = now
            this.consecutiveFailures += 1
            this.lastOutcome = outcome
        }
    }

    public func errorRecordedForCurrentIteration(): Bool {
        var recorded = false
        synchronized(this.stateLock) {
            recorded = this.consecutiveFailures > 0 && this.lastErrorAtMs >= this.lastStartedAtMs
        }
        recorded
    }

    public func currentBackoffMs(): Int64 {
        var failures: Int64 = 0
        synchronized(this.stateLock) {
            failures = this.consecutiveFailures
        }
        if (failures <= 0) {
            return 0
        }
        var delay: Int64 = 2000
        var i: Int64 = 1
        while (i < failures) {
            let next = delay * 2
            delay = if (next > 30000) { 30000 } else { next }
            i += 1
        }
        delay
    }

    public func diagnostics(): JsonObject {
        let out = JsonObject()
        synchronized(this.stateLock) {
            out.put("state", JsonString(this.pollingState))
            out.put("lastError", JsonString(this.lastError))
            out.put("lastErrorAtMs", this.lastErrorAtMs.toJsonValue())
            out.put("lastSuccessAtMs", this.lastSuccessAtMs.toJsonValue())
            out.put("lastStartedAtMs", this.lastStartedAtMs.toJsonValue())
            out.put("lastFinishedAtMs", this.lastFinishedAtMs.toJsonValue())
            out.put("consecutiveFailures", this.consecutiveFailures.toJsonValue())
            out.put("nextRetryAtMs", this.nextRetryAtMs.toJsonValue())
            out.put("lastOutcome", JsonString(this.lastOutcome))
            out.put("watchdogEnabled", true.toJsonValue())
            out.put("watchdogStallMs", this.watchdogStallMs.toJsonValue())
            out.put("watchdogIntervalMs", this.watchdogIntervalMs.toJsonValue())
            out.put("watchdogRestartCount", this.watchdogRestartCount.toJsonValue())
            out.put("transportRebuildCount", this.transportRebuildCount.toJsonValue())
            out.put("lastStallReason", JsonString(this.lastStallReason))
            out.put("lastStallAtMs", this.lastStallAtMs.toJsonValue())
            out.put("inFlightGetUpdates", (this.pollingState == "polling" && this.lastStartedAtMs > this.lastFinishedAtMs).toJsonValue())
            out.put("lastGetUpdatesStartedAtMs", this.lastStartedAtMs.toJsonValue())
            out.put("lastGetUpdatesFinishedAtMs", this.lastFinishedAtMs.toJsonValue())
            let durationMs = if (this.lastStartedAtMs > 0 && this.lastFinishedAtMs >= this.lastStartedAtMs) {
                this.lastFinishedAtMs - this.lastStartedAtMs
            } else if (this.lastStartedAtMs > 0 && this.pollingState == "polling") {
                this.nowMs() - this.lastStartedAtMs
            } else {
                0
            }
            out.put("lastGetUpdatesDurationMs", durationMs.toJsonValue())
        }
        out
    }

    public func debugSetWatchdogForTest(stallMs: Int64, intervalMs: Int64): Unit {
        synchronized(this.stateLock) {
            this.watchdogStallMs = if (stallMs > 0) { stallMs } else { this.watchdogStallMs }
            this.watchdogIntervalMs = if (intervalMs > 0) { intervalMs } else { this.watchdogIntervalMs }
        }
    }

    private func runLoop(generation: Int64): Unit {
        while (this.isActiveForGeneration(generation)) {
            let _ = this.runIterationForGeneration(generation)
            if (!this.isActiveForGeneration(generation)) {
                return
            }
            let backoffMs = this.currentBackoffMsWithJitter()
            if (backoffMs > 0) {
                this.markBackoff(backoffMs)
                this.waitForBackoff(backoffMs)
            }
        }
    }

    private func runIterationForGeneration(generation: Int64): Int64 {
        this.markStarted()
        try {
            let raw = this.fetchUpdates()
            if (!this.isActiveForGeneration(generation)) {
                return 0
            }
            if (!raw.trimAscii().isEmpty()) {
                return this.ingestUpdates(raw)
            }
        } catch (e: Exception) {
            if (this.isActiveForGeneration(generation)) {
                this.recordError("polling iteration exception: ${e.message}", outcome: "exception")
            }
        }
        0
    }

    private func currentBackoffMsWithJitter(): Int64 {
        let base = this.currentBackoffMs()
        if (base <= 0) {
            return 0
        }
        let cap = if (base / 4 < 1000) { base / 4 } else { 1000 }
        if (cap <= 0) {
            return base
        }
        let jitter = this.nowMs() % (cap + 1)
        let next = base + jitter
        if (next > 30000) { 30000 } else { next }
    }

    private func startWatchdog(): Unit {
        synchronized(this.stateLock) {
            if (this.watchdogRunning) {
                return
            }
            this.watchdogRunning = true
        }
        spawn {
            this.runWatchdogLoop()
        }
    }

    private func runWatchdogLoop(): Unit {
        while (this.watchdogShouldRun()) {
            var intervalMs: Int64 = 500
            synchronized(this.stateLock) {
                intervalMs = this.watchdogIntervalMs
            }
            sleep(Duration.millisecond * intervalMs)
            this.checkWatchdogStall()
        }
    }

    private func checkWatchdogStall(): Unit {
        let now = this.nowMs()
        var shouldRebuild = false
        var restartGeneration: Int64 = 0
        synchronized(this.stateLock) {
            if (!this.running || !this.shouldContinue()) {
                return
            }
            if (this.pollingState != "polling" || this.lastStartedAtMs <= 0 || this.lastFinishedAtMs >= this.lastStartedAtMs) {
                return
            }
            if (now - this.lastStartedAtMs <= this.watchdogStallMs) {
                return
            }
            if (this.lastStallAtMs >= this.lastStartedAtMs) {
                return
            }
            this.lastStallAtMs = now
            this.lastStallReason = "getUpdates stalled for ${now - this.lastStartedAtMs}ms"
            this.lastError = this.lastStallReason
            this.lastErrorAtMs = now
            this.pollingState = "recovering"
            this.lastOutcome = "watchdog-stall"
            this.consecutiveFailures += 1
            this.watchdogRestartCount += 1
            this.transportRebuildCount += 1
            this.loopGeneration += 1
            restartGeneration = this.loopGeneration
            shouldRebuild = true
        }
        if (shouldRebuild) {
            this.rebuildTransport()
            let generationToRestart = restartGeneration
            spawn {
                this.runLoop(generationToRestart)
            }
        }
    }

    private func markStarted(): Unit {
        let now = this.nowMs()
        synchronized(this.stateLock) {
            this.pollingState = "polling"
            this.lastStartedAtMs = now
            this.lastOutcome = "started"
            this.nextRetryAtMs = 0
        }
    }

    private func markBackoff(backoffMs: Int64): Unit {
        let now = this.nowMs()
        synchronized(this.stateLock) {
            if (this.consecutiveFailures > 0) {
                this.pollingState = "backoff"
                this.nextRetryAtMs = now + backoffMs
                this.lastOutcome = "backoff"
            }
        }
    }

    private func waitForBackoff(backoffMs: Int64): Unit {
        var remaining = backoffMs
        while (this.isActive() && remaining > 0) {
            let chunk = if (remaining < 100) { remaining } else { 100 }
            sleep(Duration.millisecond * chunk)
            remaining -= chunk
        }
    }

    private func isActive(): Bool {
        var localRunning = false
        synchronized(this.stateLock) {
            localRunning = this.running
        }
        localRunning && this.shouldContinue()
    }

    private func isActiveForGeneration(generation: Int64): Bool {
        var localRunning = false
        var localGeneration: Int64 = 0
        synchronized(this.stateLock) {
            localRunning = this.running
            localGeneration = this.loopGeneration
        }
        localRunning && localGeneration == generation && this.shouldContinue()
    }

    private func currentLoopGeneration(): Int64 {
        var generation: Int64 = 0
        synchronized(this.stateLock) {
            generation = this.loopGeneration
        }
        generation
    }

    private func watchdogShouldRun(): Bool {
        var localRunning = false
        var localWatchdogRunning = false
        synchronized(this.stateLock) {
            localRunning = this.running
            localWatchdogRunning = this.watchdogRunning
        }
        localRunning && localWatchdogRunning
    }

    private func nowMs(): Int64 {
        DateTime.now().toUnixTimeStamp().toMilliseconds()
    }
}
