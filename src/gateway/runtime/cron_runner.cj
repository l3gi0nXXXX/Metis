package metis.gateway.runtime

import metis.core.config.{CliConfig, CliSettingManager}
import metis.core.memory.DreamingPhaseRuntime
import metis.gateway.core.{
    AgentBridge,
    GatewayCronSessionReaperState,
    GatewayService,
    gatewayBridgeForSessionRequest,
    gatewayListPersistedAgentIdsForUser,
    gatewaySessionStoreForUserWithAgentId
}
import metis.gateway.session.{GatewayIngressSource, GatewaySessionRequest}
import metis.cron.{
    CronJob,
    appendCronRunLog,
    buildCronWebhookFailureBody,
    buildCronWebhookSuccessBody,
    computeJobNextRun,
    cronExecutionConversationKey,
    cronShouldRouteThroughDreaming,
    cronLoadOrEmpty,
    cronSave,
    cronStorePath,
    isCronDue,
    isTransientCronError,
    cronErrorBackoffMs,
    postCronWebhookJson,
    cronEffectiveAnnounceChannel,
    resolveCronDeliveryPlan,
    resolveCronFailurePlan
}

import magic.log.LogUtils
import magic.prelude.*

import std.collection.{ArrayList, HashMap}
import std.core.Duration
import std.fs.Path
import std.sort.sort
import std.sync.Mutex
import std.time.DateTime
import stdx.encoding.json.{JsonBool, JsonObject, JsonString}

/** 最小重触发间隔。 */
private let MIN_REFIRE_GAP_MS: Int64 = 2000

/** 运行卡住判定阈值（约 2h）。 */
private let STUCK_RUN_MS: Int64 = 2 * 60 * 60 * 1000

/** 每次启动最多立即补跑的积压任务数。 */
private let MAX_STARTUP_IMMEDIATE_RUNS: Int64 = 5

/** 启动补跑时的错峰间隔。 */
private let STARTUP_MISSED_STAGGER_MS: Int64 = 5000

/** 一次性任务的瞬时错误重试上限。 */
private let MAX_AT_TRANSIENT_RETRIES: Int64 = 3

/** 调度错误上限。 */
private let MAX_SCHEDULE_ERRORS: Int64 = 3

/** 单次 arm sleep 的最大时长。 */
private let MAX_TIMER_DELAY_MS: Int64 = 60_000

private func epochMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toMilliseconds()
}

private func computeCronArmDelayMs(jobs: ArrayList<CronJob>, nowMs: Int64): Int64 {
    var nextAt: Int64 = Int64.Max
    for (j in jobs) {
        if (!j.enabled) {
            continue
        }
        let n = j.state.nextRunAtMs
        if (n > 0 && n < nextAt) {
            nextAt = n
        }
    }
    if (nextAt == Int64.Max) {
        return MAX_TIMER_DELAY_MS
    }
    var delay = nextAt - nowMs
    if (delay < 0) {
        delay = 0
    }
    let floored = if (delay == 0) {
        MIN_REFIRE_GAP_MS
    } else {
        delay
    }
    min(floored, MAX_TIMER_DELAY_MS)
}

private func backoffDelayMs(job: CronJob, attempt: Int64): Int64 {
    let base = if (job.retryBackoffMs > 0) {
        job.retryBackoffMs
    } else {
        1000
    }
    let factor = if (attempt <= 0) {
        1
    } else {
        attempt + 1
    }
    base * factor
}

/**
 * 网关进程内定时任务执行器：提供锁、启动错峰、running 标记、错误退避等核心语义。
 */
public class CronRunner {
    private let gatewayOpt: Option<GatewayService>
    private let storePath: Path
    private let cronEnabled: Bool
    private let jobs: ArrayList<CronJob>
    private let lastFireWallMs: HashMap<String, Int64> = HashMap<String, Int64>()
    private let tickLock: Mutex = Mutex()
    private var startupCatchupDone: Bool = false
    /** 早于该时刻跳过 `tickInner`，减少 200ms 轮询下的空转。 */
    private var nextCronArmAtMs: Int64 = 0
    private let cronReaper: GatewayCronSessionReaperState = GatewayCronSessionReaperState()

    public init(
        gatewayOpt!: Option<GatewayService> = None,
        storePath!: Path = cronStorePath(CliConfig.dotDir),
        cronEnabled!: Bool = true
    ) {
        this.gatewayOpt = gatewayOpt
        this.storePath = storePath
        this.cronEnabled = cronEnabled
        this.jobs = ArrayList<CronJob>()
        for (j in cronLoadOrEmpty(storePath)) {
            this.jobs.add(j)
        }
    }

    public func storeFilePath(): Path {
        this.storePath
    }

    public static func loadJobsForDisplay(path: Path): Array<CronJob> {
        cronLoadOrEmpty(path)
    }

    private func recordScheduleComputeFailure(j: CronJob): Unit {
        j.state.scheduleErrorCount += 1
        j.state.nextRunAtMs = 0
        LogUtils.info(
            "CronRunner: schedule compute failed for job id=${j.id} count=${j.state.scheduleErrorCount}"
        )
        if (j.state.scheduleErrorCount >= MAX_SCHEDULE_ERRORS) {
            j.enabled = false
            LogUtils.error("CronRunner: auto-disabled job id=${j.id} after repeated schedule errors")
        }
    }

    private func clearStuckRunningMarkers(now: Int64): Bool {
        var changed = false
        for (j in this.jobs) {
            let r = j.state.runningAtMs
            if (r > 0 && now - r > STUCK_RUN_MS) {
                LogUtils.info("CronRunner: clearing stale runningAtMs for job id=${j.id}")
                j.state.runningAtMs = 0
                changed = true
            }
        }
        changed
    }

    private func jobExecutionInFlight(j: CronJob, now: Int64): Bool {
        let r = j.state.runningAtMs
        if (r <= 0) {
            return false
        }
        if (now - r > STUCK_RUN_MS) {
            return false
        }
        true
    }

    /**
     * 启动后首轮：若积压到期任务过多，只立即跑前 N 个，其余按当前错峰策略推迟 `nextRunAtMs`。
     */
    private func applyStartupMissedJobStaggerIfNeeded(now: Int64): Bool {
        if (this.startupCatchupDone) {
            return false
        }
        this.startupCatchupDone = true
        var due = ArrayList<CronJob>()
        for (j in this.jobs) {
            if (!j.enabled) {
                continue
            }
            if (this.jobExecutionInFlight(j, now)) {
                continue
            }
            if (j.state.nextRunAtMs > 0 && j.state.nextRunAtMs <= now) {
                due.add(j)
            }
        }
        if (due.size <= MAX_STARTUP_IMMEDIATE_RUNS) {
            return false
        }
        let arr = due.toArray()
        sort(
            arr,
            by: {
                a, b => a.state.nextRunAtMs.compare(b.state.nextRunAtMs)
            },
            stable: true
        )
        var changed = false
        var off = STARTUP_MISSED_STAGGER_MS
        var idx = MAX_STARTUP_IMMEDIATE_RUNS
        while (idx < arr.size) {
            arr[idx].state.nextRunAtMs = now + off
            off += STARTUP_MISSED_STAGGER_MS
            idx += 1
            changed = true
        }
        if (changed) {
            LogUtils.info(
                "CronRunner: staggering missed jobs (deferred ${arr.size - MAX_STARTUP_IMMEDIATE_RUNS} of ${arr.size})"
            )
        }
        changed
    }

    private func persist(): Unit {
        let fresh = cronLoadOrEmpty(this.storePath)
        if (fresh.size == 0) {
            if (this.jobs.size == 0) {
                return
            }
            cronSave(this.storePath, Array<CronJob>())
            this.jobs.clear()
            return
        }
        let memById = HashMap<String, CronJob>()
        for (j in this.jobs) {
            memById[j.id] = j
        }
        let out = ArrayList<CronJob>()
        for (d in fresh) {
            if (let Some(m) <- memById.get(d.id)) {
                d.state.nextRunAtMs = m.state.nextRunAtMs
                d.state.lastRunAtMs = m.state.lastRunAtMs
                d.state.lastError = m.state.lastError
                d.state.lastStatus = m.state.lastStatus
                d.state.consecutiveErrors = m.state.consecutiveErrors
                d.state.runningAtMs = m.state.runningAtMs
                d.state.scheduleErrorCount = m.state.scheduleErrorCount
                d.state.lastFailureAlertAtMs = m.state.lastFailureAlertAtMs
                if (m.createdAtMs > 0) {
                    d.createdAtMs = m.createdAtMs
                }
                let sk = m.schedule.kind.trimAscii().toAsciiLower()
                if (sk == "at" && !m.enabled) {
                    d.enabled = false
                }
                if (!m.enabled) {
                    d.enabled = false
                }
                out.add(d)
            } else {
                out.add(d)
            }
        }
        cronSave(this.storePath, out.toArray())
        this.jobs.clear()
        for (j in out) {
            this.jobs.add(j)
        }
    }

    private func bridgeAndRequestForJob(j: CronJob, startedAtMs: Int64): (AgentBridge, GatewaySessionRequest) {
        let request = cronBuildSessionRequest(j, startedAtMs)
        let user = CliSettingManager.readGatewaySettings()
        (gatewayBridgeForSessionRequest(user, request), request)
    }

    private func reloadJobsFromDisk(): Unit {
        this.jobs.clear()
        for (j in cronLoadOrEmpty(this.storePath)) {
            this.jobs.add(j)
        }
    }

    private func ensureSchedulesSeeded(now: Int64): Bool {
        var changed = false
        for (j in this.jobs) {
            if (!j.enabled) {
                continue
            }
            if (j.state.nextRunAtMs > 0) {
                continue
            }
            match (computeJobNextRun(j, now)) {
                case Some(nxt) =>
                    j.state.nextRunAtMs = nxt
                    j.state.scheduleErrorCount = 0
                    changed = true
                case None =>
                    j.state.nextRunAtMs = 0
                    this.recordScheduleComputeFailure(j)
                    changed = true
            }
        }
        changed
    }

    private func finalizeSuccess(j: CronJob, startedAtMs: Int64, afterRun: Int64): Unit {
        j.state.runningAtMs = 0
        j.state.lastRunAtMs = startedAtMs
        j.state.lastError = ""
        j.state.lastStatus = "success"
        j.state.consecutiveErrors = 0
        j.state.scheduleErrorCount = 0
        let sk = j.schedule.kind.trimAscii().toAsciiLower()
        if (sk == "at") {
            j.enabled = false
            j.state.nextRunAtMs = 0
            return
        }
        match (computeJobNextRun(j, afterRun)) {
            case Some(nxt) =>
                var nn = nxt
                if (sk == "cron") {
                    let minNext = afterRun + MIN_REFIRE_GAP_MS
                    if (nn < minNext) {
                        nn = minNext
                    }
                }
                j.state.nextRunAtMs = nn
            case None =>
                j.state.nextRunAtMs = 0
                this.recordScheduleComputeFailure(j)
        }
    }

    /**
     * 执行单任务一次（Agent + 投递 + finalize + run log），供 tick 与手动 run 共用。
     * 调用前须已设置 `j.state.runningAtMs = startedAtMs`。
     */
    private func fireSingleJob(j: CronJob, wallNowMs: Int64, startedAtMs: Int64): Unit {
        let dplan = resolveCronDeliveryPlan(j)
        var status = "success"
        var errMsg = ""
        var answer = ""
        var deliveryStatus = "not-requested"
        var attempt: Int64 = 0
        let maxAttempts = max(1, j.maxRetries + 1)

        try {
            let (jobBridge, jobRequest) = this.bridgeAndRequestForJob(j, startedAtMs)
            while (attempt < maxAttempts) {
                try {
                    answer = if (cronShouldRouteThroughDreaming(j)) {
                        match (DreamingPhaseRuntime.handleSystemEvent(j.systemEvent)) {
                            case Some(result) =>
                                LogUtils.info(
                                    "CronRunner: handled managed system event '${j.systemEvent}' for job id=${j.id}"
                                )
                                result
                            case None => cronBridgeReply(jobBridge, jobRequest, j.prompt, j.timeoutMs)
                        }
                    } else {
                        cronBridgeReply(jobBridge, jobRequest, j.prompt, j.timeoutMs)
                    }
                    status = "success"
                    errMsg = ""
                    break
                } catch (e: Exception) {
                    status = "error"
                    errMsg = e.message
                    LogUtils.error(
                        "CronRunner: job id=${j.id} attempt=${attempt + 1}/${maxAttempts} failed: ${e.message}"
                    )
                    if (attempt + 1 >= maxAttempts) {
                        break
                    }
                    sleep(Duration.millisecond * backoffDelayMs(j, attempt))
                }
                attempt += 1
            }

            if (status == "success" && dplan.requested) {
                let dm = dplan.mode.trimAscii().toAsciiLower()
                if (dm == "announce") {
                    let dc = cronEffectiveAnnounceChannel(dplan.channel, j.deliveryChannel)
                    let dt = dplan.to.trimAscii()
                    if (!dc.isEmpty() && !dt.isEmpty()) {
                        if (let Some(gw) <- this.gatewayOpt) {
                            let body = if (j.deliveryAnnounce) {
                                "[cron:${j.id}]\n${answer}"
                            } else {
                                answer
                            }
                            gw.sendTextToPeer(dc, dt, body)
                            deliveryStatus = "unknown"
                        } else {
                            LogUtils.info(
                                "CronRunner: job id=${j.id} 已配置 announce 投递但未注入 GatewayService，跳过 IM"
                            )
                            deliveryStatus = "not-delivered"
                        }
                    }
                } else if (dm == "webhook") {
                    let url = dplan.to.trimAscii()
                    let body = buildCronWebhookSuccessBody(
                        j.id,
                        "ok",
                        answer,
                        startedAtMs,
                        j.sessionTarget
                    )
                    if (postCronWebhookJson(url, body)) {
                        deliveryStatus = "delivered"
                    } else {
                        deliveryStatus = "not-delivered"
                    }
                }
            } else if (!dplan.requested) {
                deliveryStatus = "not-requested"
            }

            let afterRun = epochMs()
            if (status == "success") {
                this.finalizeSuccess(j, startedAtMs, afterRun)
            } else {
                this.finalizeError(j, startedAtMs, afterRun, errMsg)
                match (resolveCronFailurePlan(j, dplan)) {
                    case Some(fplan) =>
                        let fm = fplan.mode.trimAscii().toAsciiLower()
                        if (fm == "announce") {
                            let fc = cronEffectiveAnnounceChannel(fplan.channel, j.failureChannel)
                            let ft = fplan.to.trimAscii()
                            if (!fc.isEmpty() && !ft.isEmpty()) {
                                if (let Some(gw) <- this.gatewayOpt) {
                                    let body = if (j.failureAnnounce) {
                                        "[cron-failure:${j.id}] ${errMsg}"
                                    } else {
                                        errMsg
                                    }
                                    gw.sendTextToPeer(fc, ft, body)
                                }
                            }
                        } else if (fm == "webhook") {
                            let fu = fplan.to.trimAscii()
                            let fb = buildCronWebhookFailureBody(j.id, errMsg, startedAtMs, j.sessionTarget)
                            postCronWebhookJson(fu, fb)
                        }
                    case None => ()
                }
            }

            appendCronRunLog(
                this.storePath,
                j.id,
                status,
                startedAtMs,
                afterRun,
                errorMessage: errMsg,
                sessionTarget: j.sessionTarget,
                summary: answer,
                runAtMs: startedAtMs,
                nextRunAtMs: j.state.nextRunAtMs,
                deliveryStatus: deliveryStatus
            )
        } catch (fatal: Exception) {
            j.state.runningAtMs = 0
            LogUtils.error("CronRunner: unexpected failure for job id=${j.id}: ${fatal.message}")
        }
    }

    /**
     * 手动执行一次（对齐当前 `cron.run` force/due 语义）：从磁盘加载、可选到期检查、执行并持久化。
     */
    public func runJobManual(jobId: String, force: Bool): JsonObject {
        let out = JsonObject()
        synchronized(this.tickLock) {
            this.reloadJobsFromDisk()
            var now = epochMs()
            let _cleared = this.clearStuckRunningMarkers(now)
            if (_cleared) {
                this.persist()
                this.reloadJobsFromDisk()
            }
            now = epochMs()
            var target: Option<CronJob> = None<CronJob>
            for (x in this.jobs) {
                if (x.id == jobId) {
                    target = Some(x)
                }
            }
            match (target) {
                case None =>
                    out.put("ok", JsonBool(false))
                    out.put("error", JsonString("unknown job id"))
                    return out
                case Some(j) =>
                    if (!j.enabled) {
                        out.put("ok", JsonBool(false))
                        out.put("error", JsonString("job disabled"))
                        return out
                    }
                    if (this.jobExecutionInFlight(j, now)) {
                        out.put("ok", JsonBool(true))
                        out.put("ran", JsonBool(false))
                        out.put("reason", JsonString("already-running"))
                        return out
                    }
                    if (!force && !isCronDue(j.state, now, j.schedule)) {
                        out.put("ok", JsonBool(true))
                        out.put("ran", JsonBool(false))
                        out.put("reason", JsonString("not-due"))
                        return out
                    }
                    let startedAtMs = epochMs()
                    let wallNow = now
                    this.lastFireWallMs[j.id] = wallNow
                    j.state.runningAtMs = startedAtMs
                    this.fireSingleJob(j, wallNow, startedAtMs)
                    if (j.deleteAfterRun && j.state.lastStatus.trimAscii().toAsciiLower() == "success") {
                        let filtered = ArrayList<CronJob>()
                        for (x in this.jobs) {
                            if (x.id != jobId) {
                                filtered.add(x)
                            }
                        }
                        this.jobs.clear()
                        for (x in filtered) {
                            this.jobs.add(x)
                        }
                    }
                    this.persist()
                    out.put("ok", JsonBool(true))
                    out.put("ran", JsonBool(true))
                    out.put("jobId", JsonString(jobId))
                    return out
            }
        }
        out
    }

    public static func runJobOnceFromStore(
        gatewayOpt: Option<GatewayService>,
        storePath: Path,
        jobId: String,
        force: Bool,
        cronEnabled!: Bool = true
    ): JsonObject {
        let runner = CronRunner(gatewayOpt: gatewayOpt, storePath: storePath, cronEnabled: cronEnabled)
        runner.runJobManual(jobId, force)
    }

    private func finalizeError(j: CronJob, startedAtMs: Int64, afterRun: Int64, errMsg: String): Unit {
        j.state.runningAtMs = 0
        j.state.lastRunAtMs = startedAtMs
        j.state.lastStatus = "error"
        j.state.lastError = errMsg
        j.state.consecutiveErrors += 1
        let sk = j.schedule.kind.trimAscii().toAsciiLower()
        if (sk == "at") {
            if (isTransientCronError(errMsg) && j.state.consecutiveErrors <= MAX_AT_TRANSIENT_RETRIES) {
                let bo = afterRun + cronErrorBackoffMs(j.state.consecutiveErrors)
                j.state.nextRunAtMs = bo
                LogUtils.info(
                    "CronRunner: at job id=${j.id} transient error, retry scheduled at +${bo - afterRun}ms"
                )
            } else {
                j.enabled = false
                j.state.nextRunAtMs = 0
                LogUtils.info("CronRunner: at job id=${j.id} disabled after error")
            }
            return
        }
        match (computeJobNextRun(j, afterRun)) {
            case Some(natural) =>
                let bo = afterRun + cronErrorBackoffMs(j.state.consecutiveErrors)
                j.state.nextRunAtMs = max(natural, bo)
            case None =>
                j.state.scheduleErrorCount += 1
                if (j.state.scheduleErrorCount >= MAX_SCHEDULE_ERRORS) {
                    j.enabled = false
                    j.state.nextRunAtMs = 0
                    LogUtils.error(
                        "CronRunner: recurring job id=${j.id} auto-disabled after schedule errors (error path)"
                    )
                } else {
                    j.state.nextRunAtMs = afterRun + cronErrorBackoffMs(j.state.consecutiveErrors)
                }
        }
    }

    public func tick(nowOverride!: Option<Int64> = None): Unit {
        let nowPeek = match (nowOverride) {
            case Some(t) => t
            case None => epochMs()
        }
        if (this.cronEnabled && nowPeek < this.nextCronArmAtMs) {
            return
        }
        synchronized(this.tickLock) {
            let nowGate = match (nowOverride) {
                case Some(t) => t
                case None => epochMs()
            }
            if (this.cronEnabled && nowGate < this.nextCronArmAtMs) {
                return
            }
            this.tickInner(nowOverride)
            let after = epochMs()
            if (this.cronEnabled) {
                this.nextCronArmAtMs = after + computeCronArmDelayMs(this.jobs, after)
            } else {
                this.nextCronArmAtMs = after + MAX_TIMER_DELAY_MS
            }
        }
    }

    private func tickInner(nowOverride: Option<Int64>): Unit {
        if (!this.cronEnabled) {
            return
        }
        let now = match (nowOverride) {
            case Some(t) => t
            case None => epochMs()
        }
        this.reloadJobsFromDisk()
        var preChanged = this.clearStuckRunningMarkers(now)
        if (this.applyStartupMissedJobStaggerIfNeeded(now)) {
            preChanged = true
        }
        if (preChanged) {
            this.persist()
            this.reloadJobsFromDisk()
        }

        let seeded = this.ensureSchedulesSeeded(now)
        if (seeded) {
            this.persist()
            this.reloadJobsFromDisk()
        }

        var needPersistAfterFire = false
        let removeAfterRun = ArrayList<String>()
        for (j in this.jobs) {
            if (!j.enabled) {
                continue
            }
            if (this.jobExecutionInFlight(j, now)) {
                continue
            }
            if (j.state.nextRunAtMs <= 0) {
                continue
            }
            if (j.state.nextRunAtMs > now) {
                continue
            }
            if (!isCronDue(j.state, now, j.schedule)) {
                continue
            }
            if (let Some(lastWall) <- this.lastFireWallMs.get(j.id)) {
                if (now - lastWall < MIN_REFIRE_GAP_MS) {
                    continue
                }
            }

            let startedAtMs = epochMs()
            let conv = cronExecutionConversationKey(j, startedAtMs)
            LogUtils.info("CronRunner: firing job id=${j.id} conversationKey=${conv}")
            this.lastFireWallMs[j.id] = now

            j.state.runningAtMs = startedAtMs
            this.fireSingleJob(j, now, startedAtMs)
            if (j.deleteAfterRun && j.state.lastStatus.trimAscii().toAsciiLower() == "success") {
                removeAfterRun.add(j.id)
            }
            needPersistAfterFire = true
        }
        if (!removeAfterRun.isEmpty()) {
            let nextJobs = ArrayList<CronJob>()
            for (x in this.jobs) {
                var drop = false
                for (rid in removeAfterRun) {
                    if (x.id == rid) {
                        drop = true
                    }
                }
                if (!drop) {
                    nextJobs.add(x)
                }
            }
            this.jobs.clear()
            for (x in nextJobs) {
                this.jobs.add(x)
            }
        }
        if (needPersistAfterFire) {
            this.persist()
        }
        let user = CliSettingManager.readGatewaySettings()
        let retentionH = user.cronRunSessionRetentionHours
        for (agentId in gatewayListPersistedAgentIdsForUser(user)) {
            this.cronReaper.sweepIfDue(gatewaySessionStoreForUserWithAgentId(user, agentId), retentionH)
        }
    }
}

public func cronBuildSessionRequest(job: CronJob, startedAtMs: Int64): GatewaySessionRequest {
    GatewaySessionRequest(
        GatewayIngressSource.Cron,
        channelName: "cron",
        sessionHint: cronExecutionConversationKey(job, startedAtMs),
        agentId: job.agentId,
        text: job.prompt
    )
}
