package metis.cliapp

import magic.config.Config
import magic.log.LogUtils

import metis.core.config.{CliSettingManager, FeishuUserSettings, QQUserSettings, MetisPaths}
import metis.cron.{formatCronHelpForTerminal, parseSlashCronLine}
import metis.gateway.runtime.{gatewayActionsMaskSecret, gatewayActionsPrintChannelsHelp, gatewayActionsPrintStatus,
    gatewayActionsInstallPlugin, gatewayActionsPrintPluginSupportedChannels, gatewayActionsPrintPluginsList,
    gatewayActionsSetChannelEnabled, gatewayActionsSetFeishu, gatewayActionsSetMaster, gatewayActionsSetQq,
    gatewayActionsSetPluginEnabled, gatewayActionsSetPluginField,
    gatewayAnotherServeInstanceSeemsRunning, gatewayExecuteRestartServe, gatewayExecuteStopServe,
    gatewayExecuteCronWithUnifiedRun, gatewayInvokeCliAgent, gatewayLaunchDedicatedConsole, gatewayPrintCommandOutput,
    gatewayPluginHelpLines, gatewayRunChannelCli,
    runGatewaySessionsCli}
import metis.io.{InputUtils, PrintUtils, Theme, WithColor, AnsiColor}
import metis.core.skills.SkillsPrompt
import metis.program_support.{
    programSupportIsGatewayChannelCommandLine,
    programSupportIsGatewayCronCommandLine,
    programSupportIsGatewayPluginCommandLine,
    programSupportIsGatewaySessionsCommandLine,
    programSupportIsGatewaySubagentsCommandLine,
    programSupportIsMetisCommandLine
}

import std.collection.{ArrayList, filter, collectArray}
import std.fs.Path

/** 是否为 `/Metis` 交互菜单命令（大小写不敏感）。 */
protected func isMetisCommandLine(raw: String): Bool {
    programSupportIsMetisCommandLine(raw)
}

/** 顶层插件命令：`/plugin ...`。 */
protected func isGatewayPluginCommandLine(raw: String): Bool {
    programSupportIsGatewayPluginCommandLine(raw)
}

/** 顶层会话命令：`/sessions ...`。 */
protected func isGatewaySessionsCommandLine(raw: String): Bool {
    programSupportIsGatewaySessionsCommandLine(raw)
}

/** 顶层 subagent 命令：`/subagents ...`。 */
protected func isGatewaySubagentsCommandLine(raw: String): Bool {
    programSupportIsGatewaySubagentsCommandLine(raw)
}

/** 顶层渠道命令：`/channel ...`。 */
protected func isGatewayChannelCommandLine(raw: String): Bool {
    programSupportIsGatewayChannelCommandLine(raw)
}

/** 顶层定时任务命令：`/cron ...`（与 `gateway cron` 一致）。 */
protected func isGatewayCronCommandLine(raw: String): Bool {
    programSupportIsGatewayCronCommandLine(raw)
}

/** 顶层 `/cron`：与 `gateway cron` 一致。 */
protected func handleGatewayCronLine(raw: String): Unit {
    let parts = parseSlashCronLine(raw)
    if (parts.size == 0) {
        return
    }
    let (msg, _) = gatewayExecuteCronWithUnifiedRun(parts)
    let text = if (msg.contains("Usage: gateway cron")) {
        formatCronHelpForTerminal(msg)
    } else {
        msg
    }
    for (line in text.split("\n")) {
        PrintUtils.printLine(line)
    }
}

/**
 * 处理 `/Metis` 交互菜单。
 * 说明：`channel` / `sessions` / `plugin` / `cron` 已提升为顶层命令。
 */
protected func handleMetisLine(_app: CliApp, raw: String): Unit {
    let t = raw.trimAscii()
    let low = t.toAsciiLower()
    if (low == "/metis") {
        handleMetisCommand(_app)
        return
    }
    if (!low.startsWith("/metis ")) {
        return
    }
    let tokens = metisTokenize(t)
    if (tokens.size < 2) {
        handleMetisCommand(_app)
        return
    }
    let sub = tokens[1].toAsciiLower()
    match (sub) {
        case _ =>
            PrintUtils.printLine(
                "未知子命令: ${tokens[1]}。/Metis 为交互菜单入口；请优先使用 /channel、/plugin、/sessions、/cron。"
            )
    }
}

/** 顶层 `/channel`：与 `gateway channel` 一致。 */
protected func handleGatewayChannelLine(raw: String): Unit {
    let t = raw.trimAscii()
    let tokens = metisTokenize(t)
    if (tokens.size == 1) {
        handleGatewayChannelMenu()
        return
    }
    let args = ArrayList<String>()
    args.add("channel")
    var i: Int64 = 1
    while (i < tokens.size) {
        args.add(tokens[i])
        i += 1
    }
    let _ = gatewayRunChannelCli(args.toArray())
}

private func handleGatewayChannelMenu(): Unit {
    while (true) {
        let opts = [
            "list（渠道列表与扩展说明）",
            "enable（启用内置渠道）",
            "disable（禁用内置渠道）",
            "set（设置内置渠道字段）",
            "返回"
        ]
        let idx = InputUtils.getOptions(opts, prompt: "/channel")
        match (idx) {
            case None => return
            case Some(0) => gatewayActionsPrintChannelsHelp()
            case Some(1) =>
                let id = match (InputUtils.getUserInputOrCancel(prompt: "渠道 id（feishu/qq）:")) {
                    case Some(v) => v.trimAscii().toAsciiLower()
                    case None => ""
                }
                if (!id.isEmpty()) {
                    let _ = gatewayActionsSetChannelEnabled(id, true)
                }
            case Some(2) =>
                let id = match (InputUtils.getUserInputOrCancel(prompt: "渠道 id（feishu/qq）:")) {
                    case Some(v) => v.trimAscii().toAsciiLower()
                    case None => ""
                }
                if (!id.isEmpty()) {
                    let _ = gatewayActionsSetChannelEnabled(id, false)
                }
            case Some(3) =>
                let id = match (InputUtils.getUserInputOrCancel(prompt: "渠道 id（feishu/qq）:")) {
                    case Some(v) => v.trimAscii().toAsciiLower()
                    case None => ""
                }
                if (id.isEmpty()) {
                    continue
                }
                let key = match (InputUtils.getUserInputOrCancel(prompt: "字段 key:")) {
                    case Some(v) => v.trimAscii().toAsciiLower()
                    case None => ""
                }
                if (key.isEmpty()) {
                    continue
                }
                let value = match (InputUtils.getUserInputOrCancel(prompt: "字段 value:")) {
                    case Some(v) => v.trimAscii()
                    case None => ""
                }
                if (id == "feishu") {
                    let _ = gatewayActionsSetFeishu(key, value)
                } else if (id == "qq") {
                    let _ = gatewayActionsSetQq(key, value)
                } else {
                    PrintUtils.printLine("当前交互式原生字段编辑仅提供 feishu / qq。其它渠道请用 /plugin set <id> <key> <value...> 或配置文件。")
                }
            case Some(4) => return
            case _ => ()
        }
    }
}

/** 顶层 `/sessions`：与 `gateway sessions` 一致。 */
protected func handleGatewaySessionsLine(raw: String): Unit {
    let t = raw.trimAscii()
    let tokens = metisTokenize(t)
    if (tokens.size == 1) {
        handleGatewaySessionsMenu()
        return
    }
    let args = ArrayList<String>()
    args.add("sessions")
    var i: Int64 = 1
    while (i < tokens.size) {
        args.add(tokens[i])
        i += 1
    }
    let _ = runGatewaySessionsCli(args.toArray())
}

/** 顶层 `/subagents`：由统一 Gateway main runtime 处理。 */
protected func handleGatewaySubagentsLine(raw: String): Unit {
    let (ok, answer, err) = gatewayInvokeCliAgent(raw.trimAscii(), sessionKey: "main", channel: "cli")
    if (!ok) {
        PrintUtils.printLine("Gateway agent failed: ${err}")
        return
    }
    gatewayPrintCommandOutput(answer)
}

/** 顶层 `/plugin`：与 `gateway plugin` 一致。 */
protected func handleGatewayPluginLine(raw: String): Unit {
    let t = raw.trimAscii()
    let tokens = metisTokenize(t)
    if (tokens.size == 1) {
        handleGatewayPluginMenu()
        return
    }
    let sub = tokens[1].toAsciiLower()
    if (sub == "help" || sub == "-h" || sub == "--help") {
        for (line in gatewayPluginHelpLines()) {
            PrintUtils.printLine(line)
        }
        return
    }
    if (sub == "list") {
        gatewayActionsPrintPluginsList()
        return
    }
    if (sub == "list-supported") {
        let _ = gatewayActionsPrintPluginSupportedChannels()
        return
    }
    if (sub == "install" && tokens.size >= 3) {
        let name = tokens[2]
        let (appId, appSecret, force, ok) = metisPluginInstallParseFlags(tokens, 3)
        if (!ok) {
            PrintUtils.printLine("用法: /plugin install <name> [--app-id <id>] [--app-secret <secret>] [--force]")
            return
        }
        let _ = gatewayActionsInstallPlugin(name, appId: appId, appSecret: appSecret, force: force)
        return
    }
    if (sub == "enable" && tokens.size >= 3) {
        let _ = gatewayActionsSetPluginEnabled(tokens[2], true)
        return
    }
    if (sub == "disable" && tokens.size >= 3) {
        let _ = gatewayActionsSetPluginEnabled(tokens[2], false)
        return
    }
    if (sub == "set" && tokens.size >= 5) {
        let value = metisJoinFrom(tokens, 4)
        let _ = gatewayActionsSetPluginField(tokens[2], tokens[3], value)
        return
    }
    PrintUtils.printLine(
        "用法: /plugin list | list-supported | install <name> [--app-id <id>] [--app-secret <secret>] [--force] | enable <id> | disable <id> | set <id> <key> <value...> | help"
    )
}

private func handleGatewaySessionsMenu(): Unit {
    while (true) {
        let opts = [
            "list（列出会话）",
            "path（会话目录）",
            "show（查看会话转录）",
            "clear（删除会话转录）",
            "help（帮助）",
            "返回"
        ]
        let idx = InputUtils.getOptions(opts, prompt: "/sessions")
        match (idx) {
            case None => return
            case Some(0) => let _ = runGatewaySessionsCli(["sessions", "list"])
            case Some(1) => let _ = runGatewaySessionsCli(["sessions", "path"])
            case Some(2) =>
                let key = match (InputUtils.getUserInputOrCancel(prompt: "sessionKey 或 fileStem:")) {
                    case Some(v) => v.trimAscii()
                    case None => ""
                }
                if (!key.isEmpty()) {
                    let _ = runGatewaySessionsCli(["sessions", "show", key])
                }
            case Some(3) =>
                let key = match (InputUtils.getUserInputOrCancel(prompt: "要删除的 sessionKey 或 fileStem:")) {
                    case Some(v) => v.trimAscii()
                    case None => ""
                }
                if (!key.isEmpty()) {
                    let _ = runGatewaySessionsCli(["sessions", "clear", key])
                }
            case Some(4) => let _ = runGatewaySessionsCli(["sessions", "help"])
            case Some(5) => return
            case _ => ()
        }
    }
}

private func handleGatewayPluginMenu(): Unit {
    while (true) {
        let opts = [
            "list（已安装插件）",
            "list-supported（支持的平台）",
            "install（安装插件）",
            "enable（启用插件）",
            "disable（禁用插件）",
            "set（设置插件参数）",
            "返回"
        ]
        let idx = InputUtils.getOptions(opts, prompt: "/plugin")
        match (idx) {
            case None => return
            case Some(0) => gatewayActionsPrintPluginsList()
            case Some(1) =>
                let _ = gatewayActionsPrintPluginSupportedChannels()
            case Some(2) =>
                let name = match (InputUtils.getUserInputOrCancel(prompt: "插件名称（如 dingtalk）:")) {
                    case Some(v) => v.trimAscii()
                    case None => ""
                }
                if (name.isEmpty()) {
                    continue
                }
                let appId = match (InputUtils.getUserInputOrCancel(prompt: "app-id（可留空）:")) {
                    case Some(v) => v.trimAscii()
                    case None => ""
                }
                let appSecret = match (InputUtils.getUserInputOrCancel(prompt: "app-secret（可留空）:")) {
                    case Some(v) => v.trimAscii()
                    case None => ""
                }
                let _ = gatewayActionsInstallPlugin(name, appId: appId, appSecret: appSecret, force: false)
            case Some(3) =>
                let id = match (InputUtils.getUserInputOrCancel(prompt: "插件 id:")) {
                    case Some(v) => v.trimAscii()
                    case None => ""
                }
                if (!id.isEmpty()) {
                    let _ = gatewayActionsSetPluginEnabled(id, true)
                }
            case Some(4) =>
                let id = match (InputUtils.getUserInputOrCancel(prompt: "插件 id:")) {
                    case Some(v) => v.trimAscii()
                    case None => ""
                }
                if (!id.isEmpty()) {
                    let _ = gatewayActionsSetPluginEnabled(id, false)
                }
            case Some(5) =>
                let id = match (InputUtils.getUserInputOrCancel(prompt: "插件 id:")) {
                    case Some(v) => v.trimAscii()
                    case None => ""
                }
                if (id.isEmpty()) {
                    continue
                }
                let key = match (InputUtils.getUserInputOrCancel(prompt: "参数 key:")) {
                    case Some(v) => v.trimAscii()
                    case None => ""
                }
                if (key.isEmpty()) {
                    continue
                }
                let value = match (InputUtils.getUserInputOrCancel(prompt: "参数 value:")) {
                    case Some(v) => v.trimAscii()
                    case None => ""
                }
                let _ = gatewayActionsSetPluginField(id, key, value)
            case Some(6) => return
            case _ => ()
        }
    }
}

private func metisTokenize(line: String): Array<String> {
    line.split(" ") |> filter { s => !s.trimAscii().isEmpty() } |> collectArray
}

private func metisJoinFrom(parts: Array<String>, start: Int64): String {
    if (start >= parts.size) {
        return ""
    }
    var s = parts[start]
    var i = start + 1
    while (i < parts.size) {
        s = s + " " + parts[i]
        i += 1
    }
    s
}

private func metisPluginInstallParseFlags(parts: Array<String>, start: Int64): (String, String, Bool, Bool) {
    var appId = ""
    var appSecret = ""
    var force = false
    var ok = true
    var i = start
    while (i < parts.size) {
        let t = parts[i].trimAscii().toAsciiLower()
        if (t == "--force") {
            force = true
            i += 1
            continue
        }
        if (t == "--app-id") {
            if (i + 1 >= parts.size) {
                return ("", "", false, false)
            }
            appId = parts[i + 1].trimAscii()
            i += 2
            continue
        }
        if (t == "--app-secret") {
            if (i + 1 >= parts.size) {
                return ("", "", false, false)
            }
            appSecret = parts[i + 1].trimAscii()
            i += 2
            continue
        }
        ok = false
        break
    }
    (appId, appSecret, force, ok)
}

/**
 * `/Metis` 交互菜单。
 * 当前主 CLI 契约已经迁移到命令式入口；这里保留为交互式快捷入口。
 */
protected func handleMetisCommand(_app: CliApp): Unit {
    PrintUtils.printProcedure("Metis", "Interactive menu for gateway workflows")
    PrintUtils.printLine(
        "${"Tips:".withColor(Theme.MUTED)} ${"ESC".withColor(Theme.HIGHLIGHT)} 取消当前输入；原生字段表单主要覆盖 Feishu / QQ，插件渠道优先使用 /plugin 与配置文件。"
    )
    PrintUtils.printLine(
        "${"说明:".withColor(Theme.MUTED)} 这是交互式快捷菜单；CLI 主入口已改为命令式。优先使用 ${"metis gateway ...".withColor(Theme.HIGHLIGHT)}、${"metis channel ...".withColor(Theme.HIGHLIGHT)}、${"metis plugin ...".withColor(Theme.HIGHLIGHT)}。${"修改 Feishu / QQ 原生字段后须重启网关".withColor(Theme.HIGHLIGHT)}。"
    )
    PrintUtils.printLine(
        "${"会话:".withColor(Theme.MUTED)} 此菜单保留了会话快捷项；更推荐直接输入 ${"metis sessions ...".withColor(Theme.HIGHLIGHT)} 或在交互壳中使用 ${"/sessions ...".withColor(Theme.HIGHLIGHT)}。"
    )
    PrintUtils.printLine(
        "${"渠道:".withColor(Theme.MUTED)} 更推荐直接输入 ${"metis channel list".withColor(Theme.HIGHLIGHT)} 查看内置渠道与已登记插件。"
    )
    PrintUtils.printLine(
        "${"插件:".withColor(Theme.MUTED)} 插件渠道优先使用 ${"metis plugin list".withColor(Theme.HIGHLIGHT)} / ${"metis plugin enable <id>".withColor(Theme.HIGHLIGHT)} / ${"metis plugin set <id> <key> <value...>".withColor(Theme.HIGHLIGHT)}。"
    )
    PrintUtils.printLine("")
    while (true) {
        let mainOpts = [
            "查看状态（当前 metis.json 生效配置）",
            "打开网关总开关 (gateway.enabled)",
            "关闭网关总开关",
            "打开 Skills 总开关 (skills.enabled)",
            "关闭 Skills 总开关 (skills.enabled)",
            "飞书：启用",
            "飞书：禁用",
            "飞书：设置字段…",
            "QQ：启用",
            "QQ：禁用",
            "QQ：设置字段…",
            "内置渠道与扩展说明",
            "在新窗口启动网关服务（gateway serve）",
            "停止网关（gateway stop）",
            "重启网关（gateway restart：先停止再新窗口启动）",
            "Legacy 会话快捷：列出已持久化（gateway sessions list）",
            "Legacy 会话快捷：存储目录（gateway sessions path）",
            "Legacy 会话快捷：查看转录（gateway sessions show）",
            "Legacy 会话快捷：删除转录（gateway sessions clear）",
            "Legacy 会话快捷：设置 dmScope（须重启网关）",
            "Legacy 会话快捷：持久化开关（须重启网关）",
            "退出"
        ]
        let idx = InputUtils.getOptions(mainOpts, prompt: "/Metis")
        match (idx) {
            case None =>
                PrintUtils.printLine("已取消。")
                return
            case Some(21) => return
            case Some(0) =>
                gatewayActionsPrintStatus()
                let skillsEnabled = CliSettingManager.readSkillsEnabled()
                PrintUtils.printLine("Skills：skills.enabled=${skillsEnabled}".withColor(AnsiColor.WHITE))
                let gw = CliSettingManager.readGatewaySettings()
                if (gw.channelModels.isEmpty()) {
                    PrintUtils.printLine("Gateway 渠道模型绑定：未配置（使用全局 model/fallbackModels）".withColor(AnsiColor.WHITE))
                } else {
                    PrintUtils.printLine("Gateway 渠道模型绑定（gateway.channelModels）：".withColor(AnsiColor.WHITE))
                    for ((k, v) in gw.channelModels) {
                        let kk = k.trimAscii()
                        let vv = v.trimAscii()
                        if (!kk.isEmpty() && !vv.isEmpty()) {
                            PrintUtils.printLine(" - ${kk} -> ${vv}".withColor(AnsiColor.WHITE))
                        }
                    }
                }
            case Some(1) =>
                gatewayActionsSetMaster(true)
                metisHintAfterGatewaySettingsChanged()
            case Some(2) =>
                gatewayActionsSetMaster(false)
                PrintUtils.printLine("[网关] 总开关已关。若仍有「Metis Gateway」CMD 窗口在跑，请手动关闭。")
            case Some(3) =>
                CliSettingManager.writeSkillsEnabled(true)
                SkillsPrompt.invalidate()
                PrintUtils.printLine("[Skills] 已启用（metis.json: skills.enabled=true）".withColor(AnsiColor.WHITE))
            case Some(4) =>
                CliSettingManager.writeSkillsEnabled(false)
                SkillsPrompt.invalidate()
                PrintUtils.printLine("[Skills] 已禁用（metis.json: skills.enabled=false）".withColor(AnsiColor.WHITE))
            case Some(5) =>
                let _ = gatewayActionsSetChannelEnabled("feishu", true)
                metisHintAfterFeishuOrQqMutation()
            case Some(6) =>
                let _ = gatewayActionsSetChannelEnabled("feishu", false)
                metisHintAfterFeishuOrQqMutation()
            case Some(7) =>
                metisFeishuFieldPicker()
                metisHintAfterFeishuOrQqMutation()
            case Some(8) =>
                let _ = gatewayActionsSetChannelEnabled("qq", true)
                metisHintAfterFeishuOrQqMutation()
            case Some(9) =>
                let _ = gatewayActionsSetChannelEnabled("qq", false)
                metisHintAfterFeishuOrQqMutation()
            case Some(10) =>
                metisQqFieldPicker()
                metisHintAfterFeishuOrQqMutation()
            case Some(11) =>
                gatewayActionsPrintChannelsHelp()
                PrintUtils.printLine("")
            case Some(12) => let _ = gatewayLaunchDedicatedConsole()
            case Some(13) => let _ = gatewayExecuteStopServe()
            case Some(14) => let _ = gatewayExecuteRestartServe()
            case Some(15) => let _ = runGatewaySessionsCli(["sessions", "list"])
            case Some(16) => let _ = runGatewaySessionsCli(["sessions", "path"])
            case Some(17) => metisSessionShowPrompt()
            case Some(18) => metisSessionClearPrompt()
            case Some(19) => metisSessionDmScopePicker()
            case Some(20) => metisSessionPersistencePicker()
            case _ => ()
        }
    }
}

private func metisSessionShowPrompt(): Unit {
    let key = match (InputUtils.getUserInputOrCancel(prompt: "sessionKey 或 fileStem（与 gateway sessions show 一致）:")) {
        case Some(k) => k.trimAscii()
        case None => return
    }
    if (key.isEmpty()) {
        PrintUtils.printLine("已取消（空输入）。")
        return
    }
    let _ = runGatewaySessionsCli(["sessions", "show", key])
}

private func metisSessionClearPrompt(): Unit {
    let key = match (InputUtils.getUserInputOrCancel(prompt: "要删除的 sessionKey 或 fileStem:")) {
        case Some(k) => k.trimAscii()
        case None => return
    }
    if (key.isEmpty()) {
        PrintUtils.printLine("已取消（空输入）。")
        return
    }
    let ok = match (InputUtils.getUserInputOrCancel(prompt: "确认删除? 输入 yes 确认:")) {
        case Some(v) => v.trimAscii().toAsciiLower() == "yes"
        case None => false
    }
    if (!ok) {
        PrintUtils.printLine("已取消删除。")
        return
    }
    let _ = runGatewaySessionsCli(["sessions", "clear", key])
}

private func metisSessionDmScopePicker(): Unit {
    let scopes = ["per-chat", "main", "per-peer", "per-channel-peer"]
    let labels = [
        "per-chat（默认：按 chat 分桶，与历史行为一致）",
        "main（所有渠道私信共用一条 gateway:dm:main）",
        "per-peer（按发送者全局分桶；群聊慎用）",
        "per-channel-peer（私信/群聊按渠道+发送者隔离，推荐多用户）"
    ]
    let si = InputUtils.getOptions(labels, prompt: "gateway.session.dmScope")
    let i = match (si) {
        case Some(v) => v
        case None => return
    }
    let chosen = scopes[i]
    var g = CliSettingManager.readGatewaySettings()
    var sess = g.session
    sess.dmScope = chosen
    g.session = sess
    CliSettingManager.writeGatewaySettings(g)
    PrintUtils.printLine("[会话] gateway.session.dmScope = ${chosen}（已写入 metis.json）")
    metisHintAfterFeishuOrQqMutation()
}

private func metisSessionPersistencePicker(): Unit {
    let pi = InputUtils.getOptions(["开启持久化（persistenceEnabled=true）", "关闭持久化（仅内存会话）"], prompt: "gateway.session.persistenceEnabled")
    let i = match (pi) {
        case Some(v) => v
        case None => return
    }
    var g = CliSettingManager.readGatewaySettings()
    var sess = g.session
    sess.persistenceEnabled = i == 0
    g.session = sess
    CliSettingManager.writeGatewaySettings(g)
    PrintUtils.printLine("[会话] gateway.session.persistenceEnabled = ${sess.persistenceEnabled}（已写入 metis.json）")
    metisHintAfterFeishuOrQqMutation()
}

private func metisHintAfterGatewaySettingsChanged(): Unit {
    PrintUtils.printLine(
        "[网关] 需要跑网关时：启动主程序加 ${"--start-gateway-window".withColor(Theme.HIGHLIGHT)}，或在此选「在新窗口启动网关」。"
    )
    PrintUtils.printLine(
        "[网关] 若网关已在运行，${"建议选「重启网关」".withColor(Theme.HIGHLIGHT)}，使总开关等变更与当前进程一致。"
    )
    if (gatewayAnotherServeInstanceSeemsRunning()) {
        PrintUtils.printLine(
            "[网关] 检测到网关可能仍在运行。新配置需先关闭旧网关窗口，再重新打开网关。"
        )
    }
}

/** 飞书/QQ 开关或字段变更后：说明须重启 gateway serve 才会载入新配置。 */
private func metisHintAfterFeishuOrQqMutation(): Unit {
    PrintUtils.printLine(
        "[网关] ${"说明：".withColor(Theme.MUTED)} Feishu / QQ 的原生字段已写入 metis.json；${"正在运行的 gateway serve 不会自动重读文件".withColor(Theme.HIGHLIGHT)}，须重启网关后新配置才会用于连接与鉴权。插件渠道请优先使用 /plugin。"
    )
    PrintUtils.printLine(
        "[网关] 请在此选 ${"「重启网关」".withColor(Theme.HIGHLIGHT)}，或命令行执行 ${"gateway restart".withColor(Theme.HIGHLIGHT)}（亦可先「停止网关」再「在新窗口启动网关」）。"
    )
    if (gatewayAnotherServeInstanceSeemsRunning()) {
        PrintUtils.printLine(
            "[网关] 已检测到网关可能正在运行，${"请优先执行「重启网关」".withColor(Theme.HIGHLIGHT)} 以加载本次变更。"
        )
    } else {
        PrintUtils.printLine(
            "[网关] 若尚未启动网关：可选「在新窗口启动网关」，或使用 ${"--start-gateway-window".withColor(Theme.HIGHLIGHT)} 启动主程序时自动打开。"
        )
    }
}

private func feishuPreview(key: String, f: FeishuUserSettings): String {
    match (key) {
        case "app-id" => f.appId
        case "app-secret" => gatewayActionsMaskSecret(f.appSecret)
        case "receive-mode" => f.receiveMode
        case "domain" => f.domain
        case "bot-open-id" => f.botOpenId
        case "webhook-host" => f.webhookHost
        case "webhook-port" => "${f.webhookPort}"
        case "webhook-path" => f.webhookPath
        case "verification-token" => gatewayActionsMaskSecret(f.verificationToken)
        case "encrypt-key" => gatewayActionsMaskSecret(f.encryptKey)
        case "group-session-scope" => f.groupSessionScope
        case "reply-in-thread" => f.replyInThread
        case "require-signature-headers" => "${f.requireSignatureHeaders}"
        case "max-skew-seconds" => "${f.requestMaxSkewSeconds}"
        case _ => ""
    }
}

private func metisFeishuFieldPicker(): Unit {
    let keys = [
        "app-id",
        "app-secret",
        "receive-mode",
        "domain",
        "bot-open-id",
        "webhook-host",
        "webhook-port",
        "webhook-path",
        "verification-token",
        "encrypt-key",
        "group-session-scope",
        "reply-in-thread",
        "require-signature-headers",
        "max-skew-seconds"
    ]
    let labels = [
        "app-id（飞书开放平台 App ID）",
        "app-secret（App Secret）",
        "receive-mode（long_connect / webhook）",
        "domain（如 https://open.feishu.cn）",
        "bot-open-id（机器人 open_id，群 @ 判断）",
        "webhook-host",
        "webhook-port",
        "webhook-path",
        "verification-token",
        "encrypt-key",
        "group-session-scope（group / group_sender / group_topic / group_topic_sender）",
        "reply-in-thread（enabled / disabled）",
        "require-signature-headers（true/false）",
        "max-skew-seconds"
    ]
    let fi = InputUtils.getOptions(labels, prompt: "选择飞书字段")
    let i = match (fi) {
        case Some(v) => v
        case None => return
    }
    let key = keys[i]
    let f = CliSettingManager.readGatewaySettings().feishu
    let cur = feishuPreview(key, f)
    let prompt = "新值 [当前: ${cur}]（留空保留当前）:"
    let input = match (InputUtils.getUserInputOrCancel(prompt: prompt)) {
        case Some(t) => t.trimAscii()
        case None => return
    }
    let value = if (input.isEmpty()) {
        match (key) {
            case "app-id" => f.appId
            case "app-secret" => f.appSecret
            case "receive-mode" => f.receiveMode
            case "domain" => f.domain
            case "bot-open-id" => f.botOpenId
            case "webhook-host" => f.webhookHost
            case "webhook-port" => "${f.webhookPort}"
            case "webhook-path" => f.webhookPath
            case "verification-token" => f.verificationToken
            case "encrypt-key" => f.encryptKey
            case "group-session-scope" => f.groupSessionScope
            case "reply-in-thread" => f.replyInThread
            case "require-signature-headers" => "${f.requireSignatureHeaders}"
            case "max-skew-seconds" => "${f.requestMaxSkewSeconds}"
            case _ => ""
        }
    } else {
        input
    }
    let _ = gatewayActionsSetFeishu(key, value)
}

private func qqPreview(key: String, q: QQUserSettings): String {
    match (key) {
        case "mode" => q.mode
        case "app-id" => q.appId
        case "app-secret" => gatewayActionsMaskSecret(q.appSecret)
        case "bot-qq" => q.botQQ
        case "dedup-window-size" => "${q.dedupWindowSize}"
        case "official-intents" => "${q.officialIntents}"
        case "official-token-url" => q.officialTokenUrl
        case "official-gateway-url" => q.officialGatewayUrl
        case "official-ws-url" => q.officialWebsocketUrl
        case "official-auth-scheme" => q.officialAuthScheme
        case "official-send-private-url-template" => q.officialSendPrivateUrlTemplate
        case "official-send-group-url-template" => q.officialSendGroupUrlTemplate
        case _ => ""
    }
}

private func metisQqFieldPicker(): Unit {
    let keys = [
        "mode",
        "app-id",
        "app-secret",
        "bot-qq",
        "dedup-window-size",
        "official-intents",
        "official-token-url",
        "official-gateway-url",
        "official-ws-url",
        "official-auth-scheme",
        "official-send-private-url-template",
        "official-send-group-url-template"
    ]
    let labels = [
        "mode（official_ws）",
        "app-id",
        "app-secret",
        "bot-qq（gateway.qq.botQQ）",
        "dedup-cache-size（setting key: dedup-window-size）",
        "official-intents",
        "official-token-url",
        "official-gateway-url",
        "official-ws-url",
        "official-auth-scheme",
        "official-send-private-url-template",
        "official-send-group-url-template"
    ]
    let qi = InputUtils.getOptions(labels, prompt: "选择 QQ 字段")
    let i = match (qi) {
        case Some(v) => v
        case None => return
    }
    let key = keys[i]
    let q = CliSettingManager.readGatewaySettings().qq
    let cur = qqPreview(key, q)
    let prompt = "新值 [当前: ${cur}]（留空保留当前）:"
    let input = match (InputUtils.getUserInputOrCancel(prompt: prompt)) {
        case Some(t) => t.trimAscii()
        case None => return
    }
    let value = if (input.isEmpty()) {
        match (key) {
            case "mode" => q.mode
            case "app-id" => q.appId
            case "app-secret" => q.appSecret
            case "bot-qq" => q.botQQ
            case "dedup-window-size" => "${q.dedupWindowSize}"
            case "official-intents" => "${q.officialIntents}"
            case "official-token-url" => q.officialTokenUrl
            case "official-gateway-url" => q.officialGatewayUrl
            case "official-ws-url" => q.officialWebsocketUrl
            case "official-auth-scheme" => q.officialAuthScheme
            case "official-send-private-url-template" => q.officialSendPrivateUrlTemplate
            case "official-send-group-url-template" => q.officialSendGroupUrlTemplate
            case _ => ""
        }
    } else {
        input
    }
    let _ = gatewayActionsSetQq(key, value)
}
