package metis.gateway.runtime

import metis.core.config.{CliConfig, CliSettingManager}
import metis.utils.{InfoUtils, ShellUtils}

import std.collection.{ArrayList, HashSet}
import std.convert.Parsable
import std.env.atExit
import std.fs.{Path, File, FileInfo, exists, remove}
import std.sync.*
import std.time.{DateTime}
import std.core.Duration

private let LOCK_FILE: String = "gateway-serve.lock"

/** 无 pid 字段的旧版锁文件：仍用 mtime 判断；有 pid 时以进程是否存在为准。 */
private let LEGACY_LOCK_TTL: Duration = Duration.minute * 3
private let GATEWAY_STOP_TERM_WAIT_TOTAL: Duration = Duration.millisecond * 900
private let GATEWAY_STOP_TERM_WAIT_STEP: Duration = Duration.millisecond * 50
private let GATEWAY_STOP_KILL_WAIT_TOTAL: Duration = Duration.millisecond * 500
private let GATEWAY_STOP_KILL_WAIT_STEP: Duration = Duration.millisecond * 50

@When[os == "Windows"]
foreign {
    func GetCurrentProcessId(): UInt32
}

@When[os != "Windows"]
foreign {
    func getpid(): Int32
}

@When[os == "Windows"]
private func gatewayCurrentProcessId(): Int64 {
    Int64(unsafe { GetCurrentProcessId() })
}

@When[os != "Windows"]
private func gatewayCurrentProcessId(): Int64 {
    Int64(unsafe { getpid() })
}

/**
 * 常驻网关进程持有的锁路径（`~/.metis/gateway-serve.lock`）。
 */
public func gatewayServeLockPath(): Path {
    CliConfig.dotDir.join(LOCK_FILE)
}

public func gatewayConfiguredServePort(): Int64 {
    try {
        let user = CliSettingManager.readGatewaySettings()
        if (user.port > 0) {
            return user.port
        }
    } catch (_: Exception) {
        ()
    }
    18788
}

private func gatewayParseLockPid(text: String): Option<Int64> {
    for (line in text.split("\n")) {
        let t = line.trimAscii()
        if (t.startsWith("pid:")) {
            let rest = t["pid:".size..].trimAscii()
            try {
                return Some(Int64.parse(rest))
            } catch (_: Exception) {
                return None
            }
        }
    }
    None
}

public func gatewayParsePidListText(text: String): Array<Int64> {
    let result = ArrayList<Int64>()
    let seen = HashSet<Int64>()
    for (line in text.split("\n")) {
        let trimmed = line.trimAscii()
        if (trimmed.isEmpty()) {
            continue
        }
        try {
            let pid = Int64.parse(trimmed)
            if (pid > 0 && !seen.contains(pid)) {
                seen.add(pid)
                result.add(pid)
            }
        } catch (_: Exception) {
            ()
        }
    }
    result.toArray()
}

public func gatewayLooksLikeServeCommand(command: String): Bool {
    let normalized = command.trimAscii().toAsciiLower()
    if (normalized.isEmpty()) {
        return false
    }
    let looksLikeBinary =
        normalized.contains("metis") ||
        normalized.contains("magic-cli") ||
        normalized.contains("cjpm")
    let looksLikeServe = normalized.contains("gateway") && normalized.contains("serve")
    return looksLikeBinary && looksLikeServe
}

private func gatewayReadProcessCommand(pid: Int64): Option<String> {
    if (pid <= 0) {
        return None
    }
    if (InfoUtils.os == "windows") {
        return None
    }
    let (ec, out, _) = ShellUtils.execute(
        ["ps", "-o", "command=", "-p", "${pid}"],
        withWrap: false
    )
    if (ec != 0) {
        return None
    }
    let trimmed = out.trimAscii()
    if (trimmed.isEmpty()) {
        return None
    }
    Some(trimmed)
}

public func gatewayFindVerifiedListenerPidsOnPort(port!: Int64 = gatewayConfiguredServePort()): Array<Int64> {
    if (port <= 0 || InfoUtils.os == "windows") {
        return []
    }
    let (ec, out, _) = ShellUtils.execute(
        ["lsof", "-nP", "-iTCP:${port}", "-sTCP:LISTEN", "-t"],
        withWrap: false
    )
    if (ec != 0) {
        return []
    }
    let result = ArrayList<Int64>()
    for (pid in gatewayParsePidListText(out)) {
        match (gatewayReadProcessCommand(pid)) {
            case Some(command) =>
                if (gatewayLooksLikeServeCommand(command)) {
                    result.add(pid)
                }
            case None => ()
        }
    }
    result.toArray()
}

public func gatewayResolveStopTargetPids(
    listenerPids: Array<Int64>,
    lockPid!: Option<Int64> = None
): Array<Int64> {
    if (listenerPids.size > 0) {
        return listenerPids
    }
    match (lockPid) {
        case Some(pid) => if (pid > 0) { [pid] } else { [] }
        case None => []
    }
}

/** 判断指定 PID 是否仍在运行（供 CLI stop / 锁校验共用）。 */
public func gatewayServePidIsAlive(pid: Int64): Bool {
    if (pid <= 0) {
        return false
    }
    if (InfoUtils.os == "windows") {
        let (ec, out, _) = ShellUtils.execute(
            ["tasklist", "/FI", "PID eq ${pid}", "/NH"],
            withWrap: false
        )
        if (ec != 0) {
            return false
        }
        let o = out.trimAscii()
        if (o.isEmpty()) {
            return false
        }
        let lower = o.toAsciiLower()
        if (lower.contains("no tasks are running") || lower.contains("没有运行的任务")) {
            return false
        }
        return o.contains("${pid}")
    }
    let (ec2, _, _) = ShellUtils.execute(["sh", "-c", "kill -0 ${pid} 2>/dev/null"], withWrap: false)
    return ec2 == 0
}

private func gatewayWriteServeLockPayload(): String {
    let id = gatewayCurrentProcessId()
    "gateway-serve-active-v2\n${DateTime.now().format("yyyy_MM_dd-HH_mm_ss_SSS")}\npid:${id}\n"
}

private func gatewayReadLockText(p: Path): Option<String> {
    try {
        Some(String.fromUtf8(File.readFrom(p)))
    } catch (_: Exception) {
        None
    }
}

/**
 * 锁文件存在且对应进程仍在运行（或旧版锁未过期）时返回 true。
 * 若锁内 PID 已退出，会删除陈旧锁文件并返回 false。
 */
public func gatewayAnotherServeInstanceSeemsRunning(): Bool {
    if (gatewayFindVerifiedListenerPidsOnPort().size > 0) {
        return true
    }
    let p = gatewayServeLockPath()
    if (!exists(p)) {
        return false
    }
    try {
        if (let Some(text) <- gatewayReadLockText(p)) {
            if (let Some(pid) <- gatewayParseLockPid(text)) {
                if (gatewayServePidIsAlive(pid)) {
                    return true
                }
                gatewayRemoveServeLockFile()
                return false
            }
            let m = FileInfo(p).lastModificationTime
            if ((DateTime.now() - m) < LEGACY_LOCK_TTL) {
                return true
            }
            gatewayRemoveServeLockFile()
            return false
        }
        gatewayRemoveServeLockFile()
        return false
    } catch (_e: Exception) {
        false
    }
}

/**
 * 刷新锁文件（保持当前进程 PID），避免长驻进程仅因 mtime 被误判。
 */
public func gatewayRefreshServeLockMtime(): Unit {
    let p = gatewayServeLockPath()
    if (!exists(p)) {
        return
    }
    try {
        File.writeTo(p, gatewayWriteServeLockPayload().toArray())
    } catch (_e: Exception) {
        ()
    }
}

private func gatewayRemoveServeLockFile(): Unit {
    let p = gatewayServeLockPath()
    try {
        if (exists(p)) {
            remove(p)
        }
    } catch (_e: Exception) {
        ()
    }
}

/** 供 `runGatewayService` 在 `finally` 中调用（Ctrl+C 未必走 atExit）。 */
public func gatewayReleaseServeLockQuiet(): Unit {
    gatewayRemoveServeLockFile()
}

/** 读取锁文件中的网关进程 PID（不删除锁、不校验进程是否存活）。 */
public func gatewayPeekServeLockPid(): Option<Int64> {
    let p = gatewayServeLockPath()
    if (!exists(p)) {
        return None
    }
    if (let Some(text) <- gatewayReadLockText(p)) {
        return gatewayParseLockPid(text)
    }
    None
}

/** 当前进程 PID（用于避免在 serve 进程内对自己执行 stop）。 */
public func gatewayCliOwnProcessId(): Int64 {
    gatewayCurrentProcessId()
}

/**
 * 尝试结束锁文件对应的网关进程：先温和终止，必要时强制。
 * 成功后删除锁文件；返回是否已不再存活。
 */
public func gatewayTryTerminateServeProcess(pid: Int64): Bool {
    if (!gatewayServePidIsAlive(pid)) {
        gatewayRemoveServeLockFile()
        return true
    }
    if (InfoUtils.os == "windows") {
        let _ = ShellUtils.execute(["taskkill", "/PID", "${pid}", "/T"], withWrap: false)
        sleep(Duration.millisecond * 900)
        if (!gatewayServePidIsAlive(pid)) {
            gatewayRemoveServeLockFile()
            return true
        }
        let _2 = ShellUtils.execute(["taskkill", "/PID", "${pid}", "/T", "/F"], withWrap: false)
        sleep(Duration.millisecond * 500)
        if (!gatewayServePidIsAlive(pid)) {
            gatewayRemoveServeLockFile()
            return true
        }
        return false
    }
    let _t = ShellUtils.execute(["sh", "-c", "kill -TERM ${pid} 2>/dev/null"], withWrap: false)
    var waitedTerm = Duration.millisecond * 0
    while (waitedTerm < GATEWAY_STOP_TERM_WAIT_TOTAL) {
        sleep(GATEWAY_STOP_TERM_WAIT_STEP)
        waitedTerm += GATEWAY_STOP_TERM_WAIT_STEP
        if (!gatewayServePidIsAlive(pid)) {
            gatewayRemoveServeLockFile()
            return true
        }
    }
    if (!gatewayServePidIsAlive(pid)) {
        gatewayRemoveServeLockFile()
        return true
    }
    let _k = ShellUtils.execute(["sh", "-c", "kill -KILL ${pid} 2>/dev/null"], withWrap: false)
    var waitedKill = Duration.millisecond * 0
    while (waitedKill < GATEWAY_STOP_KILL_WAIT_TOTAL) {
        sleep(GATEWAY_STOP_KILL_WAIT_STEP)
        waitedKill += GATEWAY_STOP_KILL_WAIT_STEP
        if (!gatewayServePidIsAlive(pid)) {
            gatewayRemoveServeLockFile()
            return true
        }
    }
    if (!gatewayServePidIsAlive(pid)) {
        gatewayRemoveServeLockFile()
        return true
    }
    return false
}

/**
 * 在 `gateway serve` 进程内获取独占锁；失败表示已有实例在跑。
 * 成功时注册 `atExit` 清理锁文件（Ctrl+C 不一定触发 atExit，故 `runGatewayService` 另用 try/finally）。
 */
public func gatewayAcquireServeLockForRunningProcess(): Bool {
    if (gatewayAnotherServeInstanceSeemsRunning()) {
        return false
    }
    let p = gatewayServeLockPath()
    try {
        gatewayRemoveServeLockFile()
        File.writeTo(p, gatewayWriteServeLockPayload().toArray())
        atExit({
            => gatewayRemoveServeLockFile()
        })
        return true
    } catch (_e: Exception) {
        false
    }
}
