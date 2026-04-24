package metis.gateway.runtime

import metis.core.config.{CliConfig, CliSettingManager}
import metis.io.PrintUtils
import metis.utils.InfoUtils
import magic.log.LogUtils

import std.env.getVariable
import std.fs.{File, Path, canonicalize, exists}
import std.process.*
import std.time.DateTime

private func gatewayLaunchNowMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000
}

public func gatewayLaunchTimingMessage(step: String, startMs: Int64, nowMs!: Int64 = gatewayLaunchNowMs()): String {
    let elapsedMs = nowMs - startMs
    "[gateway.timing] flow=launch step=${step} elapsedMs=${elapsedMs}"
}

private func gatewayLaunchTimingLog(step: String, startMs: Int64): Unit {
    LogUtils.info(gatewayLaunchTimingMessage(step, startMs))
}

/**
 * 从 `start` 起向父目录查找含 `cjpm.toml` 的目录（用于独立网关窗口与进程 cwd 解耦于 CliConfig.cwd）。
 */
private func gatewayDirectoryContainingCjpmToml(start: Path): Option<Path> {
    try {
        var cur = canonicalize(start)
        var guard = 0
        while (guard < 96) {
            if (exists(cur.join("cjpm.toml"))) {
                return Some(cur)
            }
            let par = cur.parent
            if (par == cur) {
                break
            }
            cur = par
            guard += 1
        }
    } catch (_: Exception) {
        ()
    }
    None<Path>
}

/**
 * 运行 `cjpm run ... gateway serve` 时应使用的工程根目录。
 * 顺序：`CliConfig.cwd`（若含 cjpm.toml）→ 环境变量 `METIS_CJPM_ROOT` → 从进程当前目录向上查找 → 回退 `CliConfig.cwd`。
 */
public func gatewayCjpmProjectDirForExternalServe(): Path {
    try {
        if (exists(CliConfig.cwd.join("cjpm.toml"))) {
            return canonicalize(CliConfig.cwd)
        }
    } catch (_: Exception) {
        ()
    }
    match (getVariable("METIS_CJPM_ROOT")) {
        case Some(raw) =>
            let trimmed = raw.trimAscii()
            if (!trimmed.isEmpty()) {
                try {
                    let p = Path(trimmed)
                    if (exists(p.join("cjpm.toml"))) {
                        return canonicalize(p)
                    }
                } catch (_: Exception) {
                    ()
                }
            }
        case None => ()
    }
    match (gatewayDirectoryContainingCjpmToml(Path("."))) {
        case Some(found) => found
        case None =>
            try {
                canonicalize(CliConfig.cwd)
            } catch (_: Exception) {
                CliConfig.cwd
            }
    }
}

/**
 * 在**独立终端窗口/进程**中运行 `gateway serve`，与当前交互式 CLI 分离。
 * - Windows：生成 `.vbs`，用 `WScript.Shell` 设工作目录后 `Run cmd /k ...`，不经 `cmd /c start`，避免引号被解析成 `\\`；
 * - 其他系统：使用 `nohup` 后台运行，日志写入 `~/.metis/gateway-background.log`。
 */
public func gatewayLaunchDedicatedConsole(): Bool {
    let startMs = gatewayLaunchNowMs()
    gatewayLaunchTimingLog("enter", startMs)
    if (gatewayAnotherServeInstanceSeemsRunning()) {
        PrintUtils.printLine(
            "[网关] 检测到网关可能已在运行（~/.metis/gateway-serve.lock）。请先关闭旧网关窗口/进程，再启动，避免飞书/QQ 长连接冲突。"
        )
        gatewayLaunchTimingLog("already-running", startMs)
        return false
    }
    let user = CliSettingManager.readGatewaySettings()
    if (!user.enabled) {
        PrintUtils.printLine("[网关] 请先打开总开关（/Metis 或 gateway master on）。")
        gatewayLaunchTimingLog("disabled", startMs)
        return false
    }
    if (!gatewayHasAnyEnabledChannel(user)) {
        PrintUtils.printLine("[网关] 请至少启用飞书、QQ，或在 gateway.gatewayPlugins 中启用已注册的扩展渠道。")
        gatewayLaunchTimingLog("no-channel", startMs)
        return false
    }

    let projRoot = gatewayCjpmProjectDirForExternalServe()
    gatewayLaunchTimingLog("project-dir-resolved", startMs)
    if (!exists(projRoot.join("cjpm.toml"))) {
        PrintUtils.printLine(
            "[网关] 未在工程目录找到 cjpm.toml（已查: ${projRoot.toString()}）。请在 Metis 源码根目录执行 cjpm run，或设置环境变量 METIS_CJPM_ROOT，或在 metis.json 的 agents.defaults.workspace 指向含 cjpm.toml 的目录。"
        )
        gatewayLaunchTimingLog("missing-cjpm", startMs)
        return false
    }
    let cwd = projRoot.toString()
    try {
        if (InfoUtils.os == "windows") {
            // 不用 cmd /c start：CreateProcess 对引号的再转义易产生「找不到 \\」或 Access denied。
            let projDir = projRoot.toString().replace("\"", "\"\"")
            let vbsPath = CliConfig.dotDir.join("gateway-serve-launcher.vbs")
            let vbsText =
                "Set WshShell = CreateObject(\"WScript.Shell\")\r\n" +
                    "WshShell.CurrentDirectory = \"" +
                    projDir +
                    "\"\r\n" +
                    "WshShell.Run \"cmd /k cjpm run --name metis --run-args \"\"gateway serve\"\"\", 1, False\r\n"
            File.writeTo(vbsPath, vbsText.toArray())
            let vbsAbs = canonicalize(vbsPath).toString()
            let proc = launch(
                "wscript.exe",
                ["//nologo", vbsAbs],
                stdIn: Inherit,
                stdOut: Inherit,
                stdErr: Inherit
            )
            let _ec = proc.wait()
            PrintUtils.printLine("[网关] 已请求打开新窗口运行网关。请勿同时开多个网关（飞书长连接会冲突）。")
            gatewayLaunchTimingLog("windows-launch-done", startMs)
            return true
        }
        let logPath = CliConfig.dotDir.join("gateway-background.log")
        let logStr = logPath.toString()
        let envsetup = "/Users/l3gi0n/cangjie100/envsetup.sh"
        let opensslLibExport =
            "export DYLD_LIBRARY_PATH=\"/opt/homebrew/opt/openssl@3/lib:/opt/homebrew/opt/openssl@3.5/lib:/usr/local/opt/openssl@3/lib:\${DYLD_LIBRARY_PATH}\""
        let script =
            "cd \"${cwd}\" && " +
            "nohup /bin/zsh -lc 'source \"${envsetup}\" && ${opensslLibExport} && rtk cjpm run --skip-script --skip-build --name metis --run-args \"gateway serve\"' >> \"${logStr}\" 2>&1 &"
        let proc = launch(
            "/bin/sh",
            ["-c", script],
            stdIn: Inherit,
            stdOut: Inherit,
            stdErr: Inherit
        )
        let _ec2 = proc.wait()
        PrintUtils.printLine("[网关] 已在后台启动网关进程，日志: ${logStr}")
        gatewayLaunchTimingLog("nohup-launch-done", startMs)
        return true
    } catch (e: Exception) {
        LogUtils.error("[网关] 启动独立进程失败: ${e.message}")
        PrintUtils.printLine(
            "[网关] 自动启动失败: ${e.message}。请手动在工程目录执行: cjpm run --name metis --run-args \"gateway serve\""
        )
        gatewayLaunchTimingLog("launch-exception", startMs)
        return false
    }
}

/** 由 `CliConfig.autoStartGatewayWindow` 与调用方在启动前对锁文件的检查触发；仅当配置允许时打开独立网关窗口。 */
public func gatewayAutoLaunchDedicatedIfConfigured(): Unit {
    let user = CliSettingManager.readGatewaySettings()
    if (!user.enabled) {
        return
    }
    if (!gatewayHasAnyEnabledChannel(user)) {
        return
    }
    let _ = gatewayLaunchDedicatedConsole()
}
