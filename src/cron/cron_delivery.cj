package metis.cron

/**
 * 对齐参考实现的 `delivery.ts` / `resolveFailureDestination` 的简化版（仓颉侧无 `last` 渠道解析时回退到任务内 `deliveryChannel`）。
 */
public struct CronDeliveryResolved {
    /** `none` | `announce` | `webhook` */
    public var mode: String
    public var requested: Bool
    public var channel: String
    public var to: String

    public init(
        mode!: String = "none",
        requested!: Bool = false,
        channel!: String = "",
        to!: String = ""
    ) {
        this.mode = mode
        this.requested = requested
        this.channel = channel
        this.to = to
    }
}

public struct CronFailureResolved {
    public var mode: String
    public var channel: String
    public var to: String

    public init(mode!: String = "announce", channel!: String = "", to!: String = "") {
        this.mode = mode
        this.channel = channel
        this.to = to
    }
}

public func cronEffectiveAnnounceChannel(planChannel: String, jobFallback: String): String {
    let t = planChannel.trimAscii().toAsciiLower()
    if (t.isEmpty() || t == "last") {
        return jobFallback.trimAscii()
    }
    planChannel.trimAscii()
}

public func normalizeCronWebhookUrl(raw: String): Option<String> {
    let t = raw.trimAscii()
    if (t.isEmpty()) {
        return None<String>
    }
    let low = t.toAsciiLower()
    if (!low.startsWith("https://") && !low.startsWith("http://")) {
        return None<String>
    }
    Some(t)
}

private func isMainishSessionTarget(sessionTarget: String): Bool {
    let s = sessionTarget.trimAscii().toAsciiLower()
    s.isEmpty() || s == "main"
}

/**
 * 是否走 Dreaming 托管系统事件（仅 main 会话 + systemEvent 类 payload）。
 */
public func cronShouldRouteThroughDreaming(job: CronJob): Bool {
    if (!isMainishSessionTarget(job.sessionTarget)) {
        return false
    }
    let pk = job.payloadKind.trimAscii().toAsciiLower()
    if (pk == "systemevent") {
        return true
    }
    if (pk == "agentturn" || pk.isEmpty()) {
        return !job.systemEvent.trimAscii().isEmpty()
    }
    false
}

/**
 * 执行用会话键：`isolated`/`current` 使用一次性 `gateway:cron:run:<jobId>:<startMs>`，便于 reaper 按参考实现的 `cron:…:run:…` 语义清理。
 */
public func cronExecutionConversationKey(job: CronJob, runStartedAtMs: Int64): String {
    let sk = job.sessionKey.trimAscii()
    if (!sk.isEmpty()) {
        return sk
    }
    let st = job.sessionTarget.trimAscii().toAsciiLower()
    if (st == "isolated" || st == "current") {
        return "gateway:cron:run:${job.id}:${runStartedAtMs}"
    }
    conversationKeyForCronTarget(job.id, job.sessionTarget)
}

public func resolveCronDeliveryPlan(job: CronJob): CronDeliveryResolved {
    let dm = job.deliveryMode.trimAscii().toAsciiLower()
    let ch = job.deliveryChannel.trimAscii()
    let to = job.deliveryTo.trimAscii()
    if (dm == "none") {
        return CronDeliveryResolved(mode: "none", requested: false)
    }
    if (dm == "webhook") {
        match (normalizeCronWebhookUrl(to)) {
            case Some(u) => return CronDeliveryResolved(mode: "webhook", requested: true, to: u)
            case None => return CronDeliveryResolved(mode: "none", requested: false)
        }
    }
    if (dm == "announce") {
        if (!ch.isEmpty() && !to.isEmpty()) {
            return CronDeliveryResolved(mode: "announce", requested: true, channel: ch, to: to)
        }
        return CronDeliveryResolved(mode: "none", requested: false)
    }
    // legacy: 未显式设置 deliveryMode
    if (!ch.isEmpty() && !to.isEmpty()) {
        return CronDeliveryResolved(mode: "announce", requested: true, channel: ch, to: to)
    }
    match (normalizeCronWebhookUrl(to)) {
        case Some(u) => CronDeliveryResolved(mode: "webhook", requested: true, to: u)
        case None => CronDeliveryResolved(mode: "none", requested: false)
    }
}

private func failureModesMatchPrimary(
    primary: CronDeliveryResolved,
    fMode: String,
    fCh: String,
    fTo: String
): Bool {
    let pm = primary.mode.trimAscii().toAsciiLower()
    let fm = fMode.trimAscii().toAsciiLower()
    if (pm == "webhook" && fm == "webhook") {
        return primary.to == fTo
    }
    if (pm == "announce" && fm == "announce") {
        return primary.channel == fCh && primary.to == fTo
    }
    false
}

/**
 * 失败通知：支持 `failureDestMode` + 独立 `failureTo`/`failureChannel`，并兼容旧字段。
 */
public func resolveCronFailurePlan(job: CronJob, primary: CronDeliveryResolved): Option<CronFailureResolved> {
    let fm = job.failureDestMode.trimAscii().toAsciiLower()
    let fch = job.failureChannel.trimAscii()
    let fto = job.failureTo.trimAscii()
    let dch = job.deliveryChannel.trimAscii()
    let dto = job.deliveryTo.trimAscii()

    if (fm == "none") {
        return None<CronFailureResolved>
    }
    if (fm == "webhook") {
        match (normalizeCronWebhookUrl(fto)) {
            case Some(u) =>
                let fr = CronFailureResolved(mode: "webhook", to: u)
                if (failureModesMatchPrimary(primary, "webhook", "", u)) {
                    return None<CronFailureResolved>
                }
                return Some(fr)
            case None => return None<CronFailureResolved>
        }
    }
    if (fm == "announce") {
        let ch = if (!fch.isEmpty()) {
            fch
        } else {
            dch
        }
        let t = if (!fto.isEmpty()) {
            fto
        } else {
            dto
        }
        if (ch.isEmpty() || t.isEmpty()) {
            return None<CronFailureResolved>
        }
        if (failureModesMatchPrimary(primary, "announce", ch, t)) {
            return None<CronFailureResolved>
        }
        return Some(CronFailureResolved(mode: "announce", channel: ch, to: t))
    }
    // legacy：未设置 failureDestMode，沿用原 failureChannel/failureTo 或回退 delivery
    let lch = if (!fch.isEmpty()) {
        fch
    } else {
        dch
    }
    let lt = if (!fto.isEmpty()) {
        fto
    } else {
        dto
    }
    if (lch.isEmpty() || lt.isEmpty()) {
        return None<CronFailureResolved>
    }
    match (normalizeCronWebhookUrl(lt)) {
        case Some(u) =>
            if (failureModesMatchPrimary(primary, "webhook", "", u)) {
                return None<CronFailureResolved>
            }
            return Some(CronFailureResolved(mode: "webhook", to: u))
        case None =>
            if (failureModesMatchPrimary(primary, "announce", lch, lt)) {
                return None<CronFailureResolved>
            }
            Some(CronFailureResolved(mode: "announce", channel: lch, to: lt))
    }
}
