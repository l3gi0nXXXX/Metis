package metis.gateway.core

import magic.log.LogUtils

import std.fs.{FileInfo, exists}
import std.time.DateTime

/** 与 Metis 对齐的 `session-reaper` 最小扫描间隔。 */
public let GATEWAY_CRON_REAPER_MIN_INTERVAL_MS: Int64 = 5 * 60_000

private func isGatewayCronRunSessionKey(key: String): Bool {
    key.trimAscii().startsWith("gateway:cron:run:")
}

/**
 * 清理过期的 `gateway:cron:run:*` 转录（与当前 cron run 会话语义保持一致）。
 */
public class GatewayCronSessionReaperState {
    public var lastSweepAtMs: Int64 = 0

    public init() {}

    /** `retentionHours <= 0` 关闭。返回本趟删除的会话数。 */
    public func sweepIfDue(store: GatewaySessionStore, retentionHours: Int64): Int64 {
        if (!store.isEnabled() || retentionHours <= 0) {
            return 0
        }
        let nowMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
        if (nowMs - this.lastSweepAtMs < GATEWAY_CRON_REAPER_MIN_INTERVAL_MS) {
            return 0
        }
        this.lastSweepAtMs = nowMs
        let retentionMs = retentionHours * 3600_000
        let cutoff = nowMs - retentionMs
        var pruned: Int64 = 0
        let keys = store.listSessionKeys()
        for (k in keys) {
            if (!isGatewayCronRunSessionKey(k)) {
                continue
            }
            let p = store.transcriptPath(k)
            if (!exists(p)) {
                continue
            }
            var mtime: Int64 = 0
            try {
                mtime = FileInfo(p).lastModificationTime.toUnixTimeStamp().toMilliseconds()
            } catch (_: Exception) {
                continue
            }
            if (mtime > 0 && mtime < cutoff) {
                if (store.deleteSession(k)) {
                    pruned += 1
                }
            }
        }
        if (pruned > 0) {
            LogUtils.info(
                "CronReaper: pruned ${pruned} gateway:cron:run session(s), retentionHours=${retentionHours}"
            )
        }
        pruned
    }
}
