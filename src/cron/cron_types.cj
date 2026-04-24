package metis.cron

/**
 * 对齐参考实现的 `CronSchedule`：`every`、`at`、五段式 `cron`（`cronExpr` + `timeZone`）、可选 `staggerMs`。
 */
public struct CronSchedule {
    /**
     * `"every"` | `"at"` | `"cron"`；`cronExpr` 为五段式；`timeZone` 为 `--tz` 原文（如 UTC+8）。
     * `staggerMs`：cron 表达式在匹配时刻上的确定性错峰窗口（毫秒），0 表示不额外错峰。
     */
    CronSchedule(
        public let kind: String,
        public let everyMs: Int64,
        public let anchorMs: Int64,
        public let atMs: Int64,
        public let cronExpr: String,
        public let timeZone: String,
        public let staggerMs: Int64
    ) {}

    public static func every(intervalMs: Int64, anchorMs!: Int64 = 0): CronSchedule {
        CronSchedule("every", intervalMs, anchorMs, 0, "", "", 0)
    }

    public static func at(whenMs: Int64): CronSchedule {
        CronSchedule("at", 0, 0, whenMs, "", "", 0)
    }

    public static func cron(expr: String, timeZone: String, staggerMs!: Int64 = 0): CronSchedule {
        CronSchedule("cron", 0, 0, 0, expr.trimAscii(), timeZone.trimAscii(), staggerMs)
    }
}

/**
 * 持久化状态（对齐参考实现的 job state 思路：下次执行、上次执行、错误信息）。
 */
public class CronJobState {
    public var nextRunAtMs: Int64
    public var lastRunAtMs: Int64
    public var lastError: String
    public var lastStatus: String
    public var consecutiveErrors: Int64
    /** 与参考实现的 `runningAtMs` 对齐：>0 表示执行中，用于防重入与崩溃恢复。 */
    public var runningAtMs: Int64
    /** 连续调度计算失败次数，达到阈值可自动禁用（对齐参考实现的 `scheduleErrorCount`）。 */
    public var scheduleErrorCount: Int64
    /** 上次发出失败告警的时间（毫秒），用于 cooldown。 */
    public var lastFailureAlertAtMs: Int64

    public init(
        nextRunAtMs!: Int64 = 0,
        lastRunAtMs!: Int64 = 0,
        lastError!: String = "",
        lastStatus!: String = "",
        consecutiveErrors!: Int64 = 0,
        runningAtMs!: Int64 = 0,
        scheduleErrorCount!: Int64 = 0,
        lastFailureAlertAtMs!: Int64 = 0
    ) {
        this.nextRunAtMs = nextRunAtMs
        this.lastRunAtMs = lastRunAtMs
        this.lastError = lastError
        this.lastStatus = lastStatus
        this.consecutiveErrors = consecutiveErrors
        this.runningAtMs = runningAtMs
        this.scheduleErrorCount = scheduleErrorCount
        this.lastFailureAlertAtMs = lastFailureAlertAtMs
    }
}

/**
 * 单条定时任务：对 Agent 投递一段用户 prompt（对齐 agentTurn 类 payload）。
 *
 * `sessionTarget`：`main` | `isolated` | `session:<gatewaySessionKey>`
 */
public class CronJob {
    public let id: String
    /** 任务创建时间（Unix ms），用于 `every` 锚点回退（对齐参考实现的 `createdAtMs`）。 */
    public var createdAtMs: Int64
    public var enabled: Bool
    public var prompt: String
    public var schedule: CronSchedule
    /** 会话路由目标，见 `conversationKeyForCronTarget` */
    public var sessionTarget: String
    public var state: CronJobState
    /** 系统事件名（持久化；未接事件总线时仅记录） */
    public var systemEvent: String
    public var wakeMode: String
    /** 非空时任务结束后将 Agent 回复发往该适配器 `peerId`（如飞书 chat_id） */
    public var deliveryChannel: String
    public var deliveryTo: String
    public var deliveryAnnounce: Bool
    /** 执行超时（毫秒），<=0 视为不限制。 */
    public var timeoutMs: Int64
    /** 单次调度最多重试次数，含首次执行后的补偿重试。 */
    public var maxRetries: Int64
    /** 重试退避基准毫秒（线性/指数的基数）。 */
    public var retryBackoffMs: Int64
    /** 失败告警通道（可为空；为空时回退 deliveryChannel）。 */
    public var failureChannel: String
    public var failureTo: String
    public var failureAnnounce: Bool
    /**
     * `agentTurn` | `systemEvent`（对齐参考实现的 `payload.kind`）。
     * `systemEvent` 且会话为 main 时优先走 Dreaming 托管事件。
     */
    public var payloadKind: String
    /** `""` | `none` | `announce` | `webhook`；空串表示兼容旧版（由 channel/to 推断）。 */
    public var deliveryMode: String
    /** `""` | `none` | `announce` | `webhook`；空串表示兼容旧版 failure 字段。 */
    public var failureDestMode: String
    /** 参考实现：成功后从 store 删除（一次性任务）。 */
    public var deleteAfterRun: Bool
    public var updatedAtMs: Int64
    public var description: String
    /** 覆盖默认 Agent（持久化；执行路径按需识别）。 */
    public var agentId: String
    /** 非空时作为 `cronExecutionConversationKey` 优先于 sessionTarget。 */
    public var sessionKey: String
    public var modelOverride: String
    public var thinkingLevel: String
    public var lightContext: Bool
    public var deliveryAccountId: String
    public var bestEffortDeliver: Bool
    public var failureAccountId: String
    /** >0：连续失败 N 次后才发 failure 通知（简化为与 lastFailureAlertAtMs 配合的门槛）。 */
    public var failureAlertAfter: Int64
    public var failureAlertCooldownMs: Int64

    public init(
        id: String,
        prompt: String,
        schedule: CronSchedule,
        createdAtMs!: Int64 = 0,
        enabled!: Bool = true,
        sessionTarget!: String = "main",
        state!: CronJobState = CronJobState(),
        systemEvent!: String = "",
        wakeMode!: String = "",
        deliveryChannel!: String = "",
        deliveryTo!: String = "",
        deliveryAnnounce!: Bool = false,
        timeoutMs!: Int64 = 0,
        maxRetries!: Int64 = 0,
        retryBackoffMs!: Int64 = 1000,
        failureChannel!: String = "",
        failureTo!: String = "",
        failureAnnounce!: Bool = true,
        payloadKind!: String = "agentTurn",
        deliveryMode!: String = "",
        failureDestMode!: String = "",
        deleteAfterRun!: Bool = false,
        updatedAtMs!: Int64 = 0,
        description!: String = "",
        agentId!: String = "",
        sessionKey!: String = "",
        modelOverride!: String = "",
        thinkingLevel!: String = "",
        lightContext!: Bool = false,
        deliveryAccountId!: String = "",
        bestEffortDeliver!: Bool = false,
        failureAccountId!: String = "",
        failureAlertAfter!: Int64 = 0,
        failureAlertCooldownMs!: Int64 = 0
    ) {
        this.id = id
        this.createdAtMs = createdAtMs
        this.enabled = enabled
        this.prompt = prompt
        this.schedule = schedule
        this.sessionTarget = sessionTarget
        this.state = state
        this.systemEvent = systemEvent
        this.wakeMode = wakeMode
        this.deliveryChannel = deliveryChannel
        this.deliveryTo = deliveryTo
        this.deliveryAnnounce = deliveryAnnounce
        this.timeoutMs = timeoutMs
        this.maxRetries = maxRetries
        this.retryBackoffMs = retryBackoffMs
        this.failureChannel = failureChannel
        this.failureTo = failureTo
        this.failureAnnounce = failureAnnounce
        this.payloadKind = payloadKind
        this.deliveryMode = deliveryMode
        this.failureDestMode = failureDestMode
        this.deleteAfterRun = deleteAfterRun
        this.updatedAtMs = updatedAtMs
        this.description = description
        this.agentId = agentId
        this.sessionKey = sessionKey
        this.modelOverride = modelOverride
        this.thinkingLevel = thinkingLevel
        this.lightContext = lightContext
        this.deliveryAccountId = deliveryAccountId
        this.bestEffortDeliver = bestEffortDeliver
        this.failureAccountId = failureAccountId
        this.failureAlertAfter = failureAlertAfter
        this.failureAlertCooldownMs = failureAlertCooldownMs
    }
}

/** 由 sessionTarget 得到 AgentBridge 使用的 conversationKey */
public func conversationKeyForCronTarget(jobId: String, sessionTarget: String): String {
    let raw = sessionTarget.trimAscii()
    if (raw.isEmpty()) {
        return "gateway:cron:main"
    }
    let lower = raw.toAsciiLower()
    if (lower == "main") {
        return "gateway:cron:main"
    }
    if (lower == "isolated") {
        return "gateway:cron:isolated:${jobId}"
    }
    if (lower == "current") {
        // 与参考实现的 `normalize.ts` 一致：无 UI 会话上下文时「current」按 isolated 语义（独立会话键）
        return "gateway:cron:isolated:${jobId}"
    }
    let prefix = "session:"
    if (lower.size >= prefix.size && lower.startsWith(prefix)) {
        return raw[prefix.size..].trimAscii()
    }
    "gateway:cron:${raw}"
}
