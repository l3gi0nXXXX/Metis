package metis.gateway.runtime

import magic.jsonable.*
import metis.core.gatewayImageUnderstandingDiagnosticSnapshot
import metis.core.config.{CliConfig, CliSettingManager, MetisConfigManager, MetisPaths, GatewayUserSettings}
import metis.core.memory.MemoryRuntimeRegistry
import metis.core.skills.SkillsPrompt
import metis.core.model.CliModelManager
import metis.gateway.config.buildGatewayConfigFromUserSettings
import metis.gateway.session.GatewayIngressSource
import metis.io.PrintUtils
import metis.utils.InfoUtils

import magic.config.Config
import magic.log.LogUtils

import std.collection.{collectArray, filter, map}
import std.collection.ArrayList
import std.env.getVariable
import std.fs.{Path, exists}
import std.process.executeWithOutput
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private let GATEWAY_PREFIX: String = "gateway "

public func gatewayCliShouldPrintRuntimeRequiredHint(error: String): Bool {
    let normalized = error.trimAscii().toAsciiLower()
    normalized.contains("gateway client connect failed") ||
        normalized.contains("connect_failed") ||
        (normalized.contains("gateway") && normalized.contains("connect failed"))
}

private func gatewayCliNowMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000
}

public func gatewayCliTimingMessage(flow: String, step: String, startMs: Int64, nowMs!: Int64 = gatewayCliNowMs()): String {
    let elapsedMs = nowMs - startMs
    "[gateway.timing] flow=${flow} step=${step} elapsedMs=${elapsedMs}"
}

private func gatewayCliTimingLog(flow: String, step: String, startMs: Int64): Unit {
    LogUtils.info(gatewayCliTimingMessage(flow, step, startMs))
}

public func gatewayRestartConfigValidationMessage(): Option<String> {
    match (MetisConfigManager.currentConfigParseError()) {
        case Some(parseError) =>
            Some(
                "[网关] metis.json 解析失败，已拒绝重启并跳过任何配置持久化。请先修复配置文件后再执行 gateway restart。\n${parseError}"
            )
        case None => None
    }
}

private func gatewayCliGatewayClient(user: GatewayUserSettings): GatewayClient {
    if (user.remote.enabled) {
        return gatewayBuildClient("cli", "local-cli")
    }
    return GatewayClient(
        clientName: "cli",
        mode: "local-cli",
        transport: "local",
        gatewayUrl: "local://gateway"
    )
}

public func gatewayCliClient(): GatewayClient {
    let user = CliSettingManager.readGatewaySettings()
    gatewayCliGatewayClient(user)
}

private func concatStringArrays(a: Array<String>, b: Array<String>): Array<String> {
    let list = ArrayList<String>()
    for (x in a) {
        list.add(x)
    }
    for (x in b) {
        list.add(x)
    }
    list.toArray()
}

private func splitRunArgsTail(tail: String): Array<String> {
    tail.split(" ") |> filter { s => !s.trimAscii().isEmpty() } |> map { s => s.trimAscii() } |> collectArray
}

/**
 * 若 argv 形如 `magic-cli gateway ...` 或 `metis.exe gateway ...`，返回 `gateway` 之后的子参数切片。
 *
 * Windows 上 `cjpm run --run-args "gateway serve"` 常把整串作为**单个** argv，需解析 `gateway ...` 前缀。
 */
public func gatewaySubcommandArgs(args: Array<String>): Option<Array<String>> {
    var idx: Int64 = 0
    while (idx < args.size) {
        let a = args[idx]
        if (a == "gateway") {
            return Some(args[(idx + 1)..args.size])
        }
        if (a.size >= GATEWAY_PREFIX.size && a.startsWith(GATEWAY_PREFIX)) {
            let tail = a[GATEWAY_PREFIX.size..].trimAscii()
            let head = if (tail.isEmpty()) {
                Array<String>()
            } else {
                splitRunArgsTail(tail)
            }
            return Some(concatStringArrays(head, args[(idx + 1)..args.size]))
        }
        idx += 1
    }
    None
}

private func joinFrom(parts: Array<String>, start: Int64): String {
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

private func gatewayPluginParseInstallFlags(parts: Array<String>, start: Int64): (String, String, Bool, Bool) {
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

private func printGatewayHelp(): Unit {
    PrintUtils.printLine("Metis gateway")
    PrintUtils.printLine("Run, inspect, and query the Gateway.")
    PrintUtils.printLine("")
    PrintUtils.printLine("Usage:")
    PrintUtils.printLine("  metis gateway <subcommand> [options]")
    PrintUtils.printLine("")
    PrintUtils.printLine("Commands:")
    PrintUtils.printLine("  gateway help                     Show this help")
    PrintUtils.printLine("  gateway run                      Run the gateway in the foreground")
    PrintUtils.printLine("  gateway status                   Show gateway runtime status")
    PrintUtils.printLine("  gateway health                   Fetch the local gateway health summary")
    PrintUtils.printLine("  gateway probe                    Show local gateway reachability and status")
    PrintUtils.printLine("  gateway discover                 Discover gateway channels and plugins")
    PrintUtils.printLine("  gateway call [--json] <method> [json] Call one local gateway method with optional JSON params")
    PrintUtils.printLine("  gateway usage-cost               Show the local usage-cost summary")
    PrintUtils.printLine("  gateway master on|off            Set the gateway.enabled master switch")
    PrintUtils.printLine("  gateway serve                    Alias for gateway run")
    PrintUtils.printLine("  gateway stop                     Stop the running gateway process from the lock file")
    PrintUtils.printLine("  gateway restart                  Stop and relaunch the gateway in a new window")
    PrintUtils.printLine("  gateway channel ...              Inspect or update gateway channels")
    PrintUtils.printLine("  gateway media image ...          Inspect or update image understanding")
    PrintUtils.printLine("  gateway plugin ...               Inspect or update gateway plugins")
    PrintUtils.printLine("  gateway sessions ...             Inspect persisted gateway sessions")
    PrintUtils.printLine("  gateway subagents ...            Spawn or control background subagent runs")
    PrintUtils.printLine("  gateway cron ...                 Inspect or manage scheduled jobs")
    PrintUtils.printLine("Examples:")
    PrintUtils.printLine("  metis gateway run")
    PrintUtils.printLine("  metis gateway status")
    PrintUtils.printLine("  metis gateway discover")
    PrintUtils.printLine("  metis gateway call health")
    PrintUtils.printLine("")
    PrintUtils.printLine("Notes:")
    PrintUtils.printLine("  Interactive compatibility commands are still available inside the chat shell.")
    PrintUtils.printLine("  Gateway runtime reads persisted settings from ~/.metis/metis.json.")
}

private func gatewayMediaImageHelp(): Unit {
    PrintUtils.printLine("Metis gateway media image")
    PrintUtils.printLine("Inspect and update image understanding configuration.")
    PrintUtils.printLine("")
    PrintUtils.printLine("Usage:")
    PrintUtils.printLine("  gateway media image status [--channel shared|telegram|feishu|qq]")
    PrintUtils.printLine("  gateway media image set --provider <id> --model <model> [--channel shared|telegram|feishu|qq]")
    PrintUtils.printLine("  gateway media image add-model --provider <id> --model <model> [--channel shared|telegram|feishu|qq]")
    PrintUtils.printLine("  gateway media image remove-model --provider <id> --model <model> [--channel shared|telegram|feishu|qq]")
}

private func gatewayMediaImageFlag(args: Array<String>, key: String, start!: Int64 = 3): String {
    var i = start
    while (i < args.size) {
        if (args[i].trimAscii() == key && i + 1 < args.size) {
            return args[i + 1].trimAscii()
        }
        i += 1
    }
    ""
}

private func gatewayMediaImageNormalizeChannel(raw: String): String {
    let normalized = raw.trimAscii().toAsciiLower()
    if (normalized.isEmpty()) { "shared" } else { normalized }
}

private func gatewayMediaImageConfigForChannel(user: GatewayUserSettings, channel: String): JsonObject {
    match (gatewayMediaImageNormalizeChannel(channel)) {
        case "telegram" => user.telegram.image
        case "feishu" => user.feishu.image
        case "qq" => user.qq.image
        case _ => user.media.image
    }
}

private func gatewayMediaImageApplyChannel(user: GatewayUserSettings, channel: String, config: JsonObject): GatewayUserSettings {
    var next = user
    match (gatewayMediaImageNormalizeChannel(channel)) {
        case "telegram" => next.telegram.image = config
        case "feishu" => next.feishu.image = config
        case "qq" => next.qq.image = config
        case _ => next.media.image = config
    }
    next
}

private func gatewayMediaImageEnsureArray(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(value) =>
            try {
                value.asArray()
            } catch (_e: Exception) {
                let arr = JsonArray([])
                obj.put(key, arr)
                arr
            }
        case None =>
            let arr = JsonArray([])
            obj.put(key, arr)
            arr
    }
}

private func gatewayMediaImageEnsureObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(value) =>
            try {
                value.asObject()
            } catch (_e: Exception) {
                let child = JsonObject()
                obj.put(key, child)
                child
            }
        case None =>
            let child = JsonObject()
            obj.put(key, child)
            child
    }
}

private func gatewayMediaImageUpsertModel(config: JsonObject, provider: String, model: String, setActive: Bool): JsonObject {
    let normalizedProvider = provider.trimAscii()
    let normalizedModel = model.trimAscii()
    if (normalizedProvider.isEmpty() || normalizedModel.isEmpty()) {
        return config
    }
    let providers = gatewayMediaImageEnsureObject(config, "providers")
    let providerConfig = gatewayMediaImageEnsureObject(providers, normalizedProvider)
    providerConfig.put("kind", JsonString("chat-vision"))
    providerConfig.put("model", JsonString(normalizedModel))
    if (setActive) {
        config.put("provider", JsonString(normalizedProvider))
    }
    config.put("enabled", true.toJsonValue())
    let models = gatewayMediaImageEnsureArray(config, "models")
    var existsModel = false
    for (item in models.getItems()) {
        try {
            let row = item.asObject()
            let p = row.get("provider").getOrThrow().asString().getValue().trimAscii()
            let m = row.get("model").getOrThrow().asString().getValue().trimAscii()
            if (p == normalizedProvider && m == normalizedModel) {
                existsModel = true
            }
        } catch (_e: Exception) {
            ()
        }
    }
    if (!existsModel) {
        let entry = JsonObject()
        entry.put("provider", JsonString(normalizedProvider))
        entry.put("model", JsonString(normalizedModel))
        entry.put("capabilities", JsonArray([JsonString("image")]))
        models.add(entry)
    }
    config
}

private func gatewayMediaImageRemoveModel(config: JsonObject, provider: String, model: String): JsonObject {
    let normalizedProvider = provider.trimAscii()
    let normalizedModel = model.trimAscii()
    let nextModels = JsonArray([])
    let models = gatewayMediaImageEnsureArray(config, "models")
    for (item in models.getItems()) {
        var keep = true
        try {
            let row = item.asObject()
            let p = row.get("provider").getOrThrow().asString().getValue().trimAscii()
            let m = row.get("model").getOrThrow().asString().getValue().trimAscii()
            keep = !(p == normalizedProvider && m == normalizedModel)
        } catch (_e: Exception) {
            keep = true
        }
        if (keep) {
            nextModels.add(item)
        }
    }
    config.put("models", nextModels)
    config
}

private func gatewayRunMediaImageCli(sub: Array<String>): Int64 {
    if (sub.size < 3 || sub[2] == "help" || sub[2] == "-h" || sub[2] == "--help") {
        gatewayMediaImageHelp()
        return 0
    }
    let action = sub[2].trimAscii().toAsciiLower()
    let channel = gatewayMediaImageNormalizeChannel(gatewayMediaImageFlag(sub, "--channel"))
    if (action == "status") {
        let user = CliSettingManager.readGatewaySettings()
        let targetChannel = if (channel == "shared") { "telegram" } else { channel }
        let result = gatewayImageUnderstandingDiagnosticSnapshot(user, channel: targetChannel)
        result.put("configChannel", JsonString(channel))
        gatewayPrintCommandOutput(result.toJsonString())
        return 0
    }
    if (action == "set" || action == "add-model" || action == "remove-model") {
        let provider = gatewayMediaImageFlag(sub, "--provider")
        let model = gatewayMediaImageFlag(sub, "--model")
        if (provider.isEmpty() || model.isEmpty()) {
            PrintUtils.printLine("Usage: gateway media image ${action} --provider <id> --model <model> [--channel shared|telegram|feishu|qq]")
            return 1
        }
        let user = CliSettingManager.readGatewaySettings()
        let current = gatewayMediaImageConfigForChannel(user, channel)
        let nextConfig = if (action == "remove-model") {
            gatewayMediaImageRemoveModel(current, provider, model)
        } else {
            gatewayMediaImageUpsertModel(current, provider, model, action == "set")
        }
        let nextUser = gatewayMediaImageApplyChannel(user, channel, nextConfig)
        CliSettingManager.writeGatewaySettings(nextUser)
        let result = JsonObject()
        result.put("ok", true.toJsonValue())
        result.put("channel", JsonString(channel))
        result.put("action", JsonString(action))
        result.put("image", nextConfig)
        gatewayPrintCommandOutput(result.toJsonString())
        return 0
    }
    gatewayMediaImageHelp()
    1
}

private func gatewayRunForeground(flowName!: String = "run"): Int64 {
    let startMs = gatewayCliNowMs()
    gatewayCliTimingLog(flowName, "enter", startMs)
    PrintUtils.printLine("[gateway] model: ${CliConfig.model}")
    PrintUtils.printLine("[gateway] log file: ${Config.logFile}")
    runGatewayService()
    gatewayCliTimingLog(flowName, "exit", startMs)
    0
}

private func gatewayPrintHealth(): Unit {
    let res = gatewayCliClient().call("health")
    gatewayPrintCommandOutput(res.toJson().toJsonString())
}

private func gatewayPrintProbe(): Unit {
    let health = gatewayCliClient().call("health")
    let status = gatewayCliClient().call("status")
    PrintUtils.printLine("Gateway Probe")
    gatewayPrintCommandOutput(health.toJson().toJsonString())
    gatewayPrintCommandOutput(status.toJson().toJsonString())
}

private func gatewayPrintDiscover(): Unit {
    let res = gatewayCliClient().call("discover")
    gatewayPrintCommandOutput(res.toJson().toJsonString())
}

private func gatewayParseCallParams(raw: String): JsonObject {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return JsonObject()
    }
    try {
        JsonValue.fromStr(trimmed).asObject()
    } catch (_e: Exception) {
        let obj = JsonObject()
        obj.put("raw", JsonString(trimmed))
        obj
    }
}

private func gatewayCallLocalMethod(methodRaw: String, paramsRaw!: String = "", json!: Bool = false): Int64 {
    let method = methodRaw.trimAscii().toAsciiLower()
    if (method.isEmpty()) {
        PrintUtils.printLine("Usage: gateway call [--json] <method> [json-params]")
        return 1
    }
    let params = gatewayParseCallParams(paramsRaw)
    let res = gatewayCliClient().call(method, params: params)
    let raw = res.toJson().toJsonString()
    if (json) {
        PrintUtils.printLine(raw)
    } else {
        gatewayPrintCommandOutput(raw)
    }
    if (res.ok) { 0 } else { 1 }
}

private func gatewayRunCallCli(sub: Array<String>): Int64 {
    if (sub.size < 2) {
        PrintUtils.printLine("Usage: gateway call [--json] <method> [json-params]")
        return 1
    }
    var json = false
    let parts = ArrayList<String>()
    var i: Int64 = 1
    while (i < sub.size) {
        let t = sub[i].trimAscii()
        if (t.toAsciiLower() == "--json") {
            json = true
        } else {
            parts.add(sub[i])
        }
        i += 1
    }
    if (parts.size == 0) {
        PrintUtils.printLine("Usage: gateway call [--json] <method> [json-params]")
        return 1
    }
    gatewayCallLocalMethod(parts[0], paramsRaw: joinFrom(parts.toArray(), 1), json: json)
}

private func gatewayPrintUsageCost(): Unit {
    let res = gatewayCliClient().call("usage-cost")
    gatewayPrintCommandOutput(res.toJson().toJsonString())
}

private func gatewayChannelRpcParams(channelId: String): JsonObject {
    let params = JsonObject()
    if (!channelId.trimAscii().isEmpty()) {
        params.put("channelId", JsonString(channelId.trimAscii().toAsciiLower()))
    }
    params
}

private func gatewayChannelLifecycleParams(channelId: String, accountId: String): JsonObject {
    let params = gatewayChannelRpcParams(channelId)
    if (!accountId.trimAscii().isEmpty()) {
        params.put("accountId", JsonString(accountId.trimAscii()))
    }
    params
}

private func gatewayChannelLifecycleResultString(result: JsonObject, key: String, defaultValue!: String = ""): String {
    match (result.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_e: Exception) { defaultValue }
        case None => defaultValue
    }
}

private func gatewayPrintChannelLifecycleResponse(res: GatewayRpcResponse, action: String): Unit {
    let result = try { res.result.asObject() } catch (_e: Exception) { JsonObject() }
    let channelId = gatewayChannelLifecycleResultString(result, "channelId", defaultValue: gatewayChannelLifecycleResultString(result, "channel"))
    let accountId = gatewayChannelLifecycleResultString(result, "accountId")
    let actionResult = gatewayChannelLifecycleResultString(result, "result", defaultValue: if (res.ok) { "ok" } else { "failed" })
    let reason = gatewayChannelLifecycleResultString(result, "reason")
    PrintUtils.printLine("Channel: ${channelId}")
    PrintUtils.printLine("Account: ${if (accountId.isEmpty()) { "all" } else { accountId }}")
    PrintUtils.printLine("Action: ${action}")
    PrintUtils.printLine("Result: ${actionResult}")
    if (!reason.isEmpty()) {
        PrintUtils.printLine("Reason: ${reason}")
    }
}

private func gatewayRunChannelLifecycleCli(sub: Array<String>, action: String): Int64 {
    var json = false
    var channelId = ""
    var accountId = ""
    var i: Int64 = 2
    while (i < sub.size) {
        let token = sub[i].trimAscii()
        let low = token.toAsciiLower()
        if (low == "--json") {
            json = true
            i += 1
            continue
        }
        if (low == "--account") {
            if (i + 1 >= sub.size) {
                PrintUtils.printLine("Usage: gateway channel ${action} <id> [--account <accountId>] [--json]")
                return 1
            }
            accountId = sub[i + 1].trimAscii()
            i += 2
            continue
        }
        if (channelId.isEmpty()) {
            channelId = token
            i += 1
            continue
        }
        PrintUtils.printLine("Unknown gateway channel ${action} option: ${token}")
        PrintUtils.printLine("Usage: gateway channel ${action} <id> [--account <accountId>] [--json]")
        return 1
    }
    if (channelId.trimAscii().isEmpty()) {
        PrintUtils.printLine("Usage: gateway channel ${action} <id> [--account <accountId>] [--json]")
        return 1
    }
    let method = "channels.${action}"
    let res = gatewayCliClient().call(method, params: gatewayChannelLifecycleParams(channelId, accountId))
    if (json) {
        PrintUtils.printLine(res.toJson().toJsonString())
    } else {
        gatewayPrintChannelLifecycleResponse(res, action)
    }
    if (res.ok) { 0 } else { 1 }
}

private func gatewayPrintChannelHelp(): Unit {
    PrintUtils.printLine("Metis gateway channel")
    PrintUtils.printLine("Inspect and update gateway channels.")
    PrintUtils.printLine("")
    PrintUtils.printLine("Usage:")
    PrintUtils.printLine("  gateway channel list")
    PrintUtils.printLine("  gateway channel health [id] [--json]")
    PrintUtils.printLine("  gateway channel runtime [id] [--json]")
    PrintUtils.printLine("  gateway channel get <id> [--json]")
    PrintUtils.printLine("  gateway channel audit [id] [--json]")
    PrintUtils.printLine("  gateway channel start <id> [--account <accountId>] [--json]")
    PrintUtils.printLine("  gateway channel stop <id> [--account <accountId>] [--json]")
    PrintUtils.printLine("  gateway channel restart <id> [--account <accountId>] [--json]")
    PrintUtils.printLine("  gateway channel enable <id>")
    PrintUtils.printLine("  gateway channel disable <id>")
    PrintUtils.printLine("  gateway channel set <feishu|qq> <key> <value...>")
    PrintUtils.printLine("")
    PrintUtils.printLine("Notes:")
    PrintUtils.printLine("  `gateway channels ...` is accepted as an alias for `gateway channel ...`.")
    PrintUtils.printLine("  Gateway output is summarized for humans; dedicated RPC surfaces still carry the full structured data.")
}

public func gatewayRunChannelCli(sub: Array<String>): Int64 {
    if (sub.size < 2 || sub[1] == "help" || sub[1] == "-h" || sub[1] == "--help") {
        gatewayPrintChannelHelp()
        return 0
    }
    let subcmd = sub[1].trimAscii().toAsciiLower()
    if (subcmd == "list") {
        gatewayActionsPrintChannelsHelp()
        return 0
    }
    if (subcmd == "start" || subcmd == "stop" || subcmd == "restart") {
        return gatewayRunChannelLifecycleCli(sub, subcmd)
    }
    if (subcmd == "health" || subcmd == "runtime" || subcmd == "audit" || subcmd == "get") {
        var channelId = ""
        var json = false
        var idx: Int64 = 2
        while (idx < sub.size) {
            let token = sub[idx].trimAscii()
            if (token.toAsciiLower() == "--json") {
                json = true
            } else if (channelId.isEmpty()) {
                channelId = token
            } else {
                PrintUtils.printLine("Unknown gateway channel ${subcmd} option: ${token}")
                PrintUtils.printLine("Usage: gateway channel ${subcmd}${if (subcmd == "get") { " <id>" } else { " [id]" }} [--json]")
                return 1
            }
            idx += 1
        }
        if (subcmd == "get" && channelId.isEmpty()) {
            PrintUtils.printLine("Usage: gateway channel get <id> [--json]")
            return 1
        }
        let method = match (subcmd) {
            case "health" => "channels.health"
            case "runtime" => "channels.runtime"
            case "audit" => "channels.audit"
            case _ => "channels.get"
        }
        let res = gatewayCliClient().call(method, params: gatewayChannelRpcParams(channelId))
        if (json) {
            PrintUtils.printLine(res.toJson().toJsonString())
        } else {
            gatewayPrintCommandOutput(res.toJson().toJsonString())
        }
        return if (res.ok) { 0 } else { 1 }
    }
    if (subcmd == "enable") {
        if (sub.size < 3) {
            PrintUtils.printLine("Usage: gateway channel enable <id>")
            return 1
        }
        return if (gatewayActionsSetChannelEnabled(sub[2].trimAscii().toAsciiLower(), true)) {
            0
        } else {
            1
        }
    }
    if (subcmd == "disable") {
        if (sub.size < 3) {
            PrintUtils.printLine("Usage: gateway channel disable <id>")
            return 1
        }
        return if (gatewayActionsSetChannelEnabled(sub[2].trimAscii().toAsciiLower(), false)) {
            0
        } else {
            1
        }
    }
    if (subcmd == "set") {
        if (sub.size < 5) {
            PrintUtils.printLine("Usage: gateway channel set <feishu|qq> <key> <value...>")
            return 1
        }
        let cid = sub[2].trimAscii().toAsciiLower()
        let key = sub[3].trimAscii().toAsciiLower()
        let value = joinFrom(sub, 4)
        if (cid == "feishu") {
            return if (gatewayActionsSetFeishu(key, value)) { 0 } else { 1 }
        }
        if (cid == "qq") {
            return if (gatewayActionsSetQq(key, value)) { 0 } else { 1 }
        }
        PrintUtils.printLine("Interactive native field editing currently supports feishu and qq only.")
        PrintUtils.printLine("Try: gateway channel list")
        return 1
    }
    PrintUtils.printLine("Unknown gateway channel subcommand: ${subcmd}")
    PrintUtils.printLine("Try: gateway channel help")
    1
}

public func gatewayPluginHelpLines(): Array<String> {
    [
        "Metis gateway plugin",
        "Inspect and update installed Gateway plugins.",
        "",
        "Usage:",
        "  gateway plugin list",
        "  gateway plugin list-supported",
        "  gateway plugin install <name> [--app-id <id>] [--app-secret <secret>] [--force]",
        "  gateway plugin enable <id>",
        "  gateway plugin disable <id>",
        "  gateway plugin set <id> <key> <value...>",
        "",
        "Notes:",
        "  `gateway plugins ...` is accepted as an alias for `gateway plugin ...`.",
        "  Plugin configuration writes update metis.json; restart gateway serve if the running process must reload settings."
    ]
}

private func gatewayPrintPluginHelp(): Unit {
    for (line in gatewayPluginHelpLines()) {
        PrintUtils.printLine(line)
    }
}

private func gatewayDashboardBuildUrl(): String {
    let (_, token) = gatewayDashboardResolveToken()
    let user = CliSettingManager.readGatewaySettings()
    let cfg = buildGatewayConfigFromUserSettings(user)
    let binding = GatewayControlUiRuntime.controlUiBinding(cfg)
    if (token.isEmpty()) {
        return binding.httpUrl
    }
    "${binding.httpUrl}#token=${token}"
}

private func gatewayDashboardAssetModeSummary(): (String, String, String) {
    let user = CliSettingManager.readGatewaySettings()
    let cfg = buildGatewayConfigFromUserSettings(user)
    let snapshot = gatewayControlUiSnapshotJson(cfg)
    let assetMode = match (snapshot.get("assetMode")) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { "inline-fallback" }
        case None => "inline-fallback"
    }
    let rootState = gatewayControlUiRootStateJson(cfg)
    let rootKind = match (rootState.get("kind")) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
    let rootMessage = match (rootState.get("message")) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
    (assetMode, rootKind, rootMessage)
}

private func gatewayDashboardResolveToken(): (String, String) {
    let user = CliSettingManager.readGatewaySettings()
    match (getVariable("CANGJIECLAW_GATEWAY_TOKEN")) {
        case Some(token) =>
            let trimmed = token.trimAscii()
            if (!trimmed.isEmpty()) {
                return ("env", trimmed)
            }
        case None => ()
    }
    let token = gatewayPreferredAuthTokenFromSettings(user).trimAscii()
    if (!token.isEmpty()) {
        return ("config", token)
    }
    ("none", "")
}

private func gatewayDashboardShellSingleQuote(raw: String): String {
    "'" + raw.replace("'", "'\"'\"'") + "'"
}

private func gatewayDashboardTryCopy(url: String): Bool {
    let (exitCode, _, _) = match (InfoUtils.os) {
        case "macos" =>
            executeWithOutput(
                "osascript",
                ["-e", "on run argv", "-e", "set the clipboard to (item 1 of argv)", "-e", "end run", url],
                workingDirectory: CliConfig.cwd
            )
        case "linux" =>
            let escaped = gatewayDashboardShellSingleQuote(url)
            let xclip = executeWithOutput(
                "sh",
                ["-lc", "printf %s ${escaped} | xclip -selection clipboard"],
                workingDirectory: CliConfig.cwd
            )
            if (xclip[0] == 0) {
                xclip
            } else {
                executeWithOutput(
                    "sh",
                    ["-lc", "printf %s ${escaped} | wl-copy"],
                    workingDirectory: CliConfig.cwd
                )
            }
        case "windows" =>
            executeWithOutput(
                "powershell",
                ["-NoProfile", "-Command", "Set-Clipboard -Value $args[0]", url],
                workingDirectory: CliConfig.cwd
            )
        case _ => (-1, Array<Byte>(), Array<Byte>())
    }
    exitCode == 0
}

private func gatewayDashboardOpenHint(url: String): String {
    let user = CliSettingManager.readGatewaySettings()
    let cfg = buildGatewayConfigFromUserSettings(user)
    let host = gatewayHttpListenHost(cfg)
    let port = cfg.port
    if (host == "127.0.0.1" || host == "localhost") {
        return "Browser launch failed. Open the URL above manually."
    }
    "Browser launch failed. If this gateway is remote, create an SSH tunnel like `ssh -L ${port}:${host}:${port} <host>` and then open ${url}."
}

private func gatewayDashboardTryOpen(url: String): Bool {
    let (exitCode, _, _) = match (InfoUtils.os) {
        case "macos" => executeWithOutput("open", [url], workingDirectory: CliConfig.cwd)
        case "linux" => executeWithOutput("xdg-open", [url], workingDirectory: CliConfig.cwd)
        case "windows" => executeWithOutput("rundll32", ["url.dll,FileProtocolHandler", url], workingDirectory: CliConfig.cwd)
        case _ => (-1, Array<Byte>(), Array<Byte>())
    }
    exitCode == 0
}

private func gatewayCliJsonString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func gatewayCliJsonBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
}

private func gatewayCliFormatVerboseAnswer(answer: String, invoke: JsonObject, verbose: String): String {
    let mode = verbose.trimAscii().toAsciiLower()
    if (mode.isEmpty()) {
        return answer
    }
    let lines = ArrayList<String>()
    lines.add(answer)
    if (mode == "routing" || mode == "full") {
        lines.add("")
        lines.add("[routing]")
        lines.add("agent=${gatewayCliJsonString(invoke, "agentId")}")
        lines.add("session=${gatewayCliJsonString(invoke, "session")}")
        let to = gatewayCliJsonString(invoke, "to")
        if (!to.isEmpty()) {
            lines.add("to=${to}")
        }
        let lane = gatewayCliJsonString(invoke, "lane")
        if (!lane.isEmpty()) {
            lines.add("lane=${lane}")
        }
    }
    if (mode == "delivery" || mode == "full") {
        lines.add("")
        lines.add("[delivery]")
        lines.add("requested=${gatewayCliJsonBool(invoke, "deliver")}")
        lines.add("status=${gatewayCliJsonString(invoke, "deliveryStatus")}")
        let err = gatewayCliJsonString(invoke, "deliveryError")
        if (!err.isEmpty()) {
            lines.add("error=${err}")
        }
        lines.add("bestEffort=${gatewayCliJsonBool(invoke, "bestEffortDeliver")}")
    }
    if (mode == "full") {
        lines.add("")
        lines.add("[invoke]")
        let runId = gatewayCliJsonString(invoke, "runId")
        if (!runId.isEmpty()) {
            lines.add("runId=${runId}")
        }
        lines.add("thinking=${gatewayCliJsonString(invoke, "thinking")}")
        let timeout = gatewayCliJsonString(invoke, "timeout")
        if (!timeout.isEmpty()) {
            lines.add("timeout=${timeout}s")
        }
        lines.add("idempotentReplay=${gatewayCliJsonBool(invoke, "idempotentReplay")}")
    }
    String.join(lines.toArray(), delimiter: "\n")
}

public func gatewayInvokeCliAgentResult(
    message: String,
    sessionKey!: String = "main",
    channel!: String = "cli",
    to!: String = "",
    agentId!: String = "",
    thinking!: String = "",
    verbose!: String = "",
    timeoutSeconds!: Int64 = 0,
    deliver!: Bool = false,
    bestEffortDeliver!: Bool = false,
    lane!: String = "",
    runId!: String = "",
    extraSystemPrompt!: String = "",
    replyTo!: String = "",
    replyChannel!: String = "",
    replyAccount!: String = "",
    replyToMessageId!: String = "",
    replyInThread!: Bool = false
): (Bool, JsonObject, String) {
    let prompt = message.trimAscii()
    if (prompt.isEmpty()) {
        return (false, JsonObject(), "message must be non-empty")
    }
    let params = gatewayBuildAgentInvokeRpcParams(
        GatewayIngressSource.Cli,
        sessionKey: sessionKey,
        text: prompt,
        channel: channel,
        agentId: agentId,
        to: to,
        lane: lane,
        deliver: deliver,
        thinking: thinking,
        verbose: verbose,
        timeoutSeconds: timeoutSeconds,
        bestEffortDeliver: bestEffortDeliver,
        replyChannel: replyChannel,
        replyTo: replyTo,
        replyAccount: replyAccount,
        replyToMessageId: replyToMessageId,
        replyInThread: replyInThread,
        extraSystemPrompt: extraSystemPrompt,
        idempotencyKey: runId
    )
    try {
        let response = gatewayCliClient().request("agent.invoke", params: params)
        if (!response.ok) {
            return (false, JsonObject(), response.error)
        }
        let result = try {
            response.result.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        (true, result, "")
    } catch (ex: Exception) {
        (false, JsonObject(), ex.message)
    }
}

public func gatewayInvokeCliAgent(
    message: String,
    sessionKey!: String = "main",
    channel!: String = "cli",
    to!: String = "",
    agentId!: String = "",
    thinking!: String = "",
    verbose!: String = "",
    timeoutSeconds!: Int64 = 0,
    deliver!: Bool = false,
    bestEffortDeliver!: Bool = false,
    lane!: String = "",
    runId!: String = "",
    extraSystemPrompt!: String = "",
    replyTo!: String = "",
    replyChannel!: String = "",
    replyAccount!: String = "",
    replyToMessageId!: String = "",
    replyInThread!: Bool = false
): (Bool, String, String) {
    let (ok, result, err) = gatewayInvokeCliAgentResult(
        message,
        sessionKey: sessionKey,
        channel: channel,
        to: to,
        agentId: agentId,
        thinking: thinking,
        verbose: verbose,
        timeoutSeconds: timeoutSeconds,
        deliver: deliver,
        bestEffortDeliver: bestEffortDeliver,
        lane: lane,
        runId: runId,
        extraSystemPrompt: extraSystemPrompt,
        replyTo: replyTo,
        replyChannel: replyChannel,
        replyAccount: replyAccount,
        replyToMessageId: replyToMessageId,
        replyInThread: replyInThread
    )
    if (!ok) {
        return (false, "", err)
    }
    let invoke = match (result.get("invoke")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let answer = match (invoke.get("answer")) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
    if (answer.trimAscii().isEmpty()) {
        return (false, "", "gateway agent invoke returned no answer")
    }
    (true, gatewayCliFormatVerboseAnswer(answer, invoke, verbose), "")
}

public func runGatewayDashboardCli(args: Array<String>): Int64 {
    applyRuntimeForGatewayServe()

    var shouldOpen = true
    for (arg in args) {
        let token = arg.trimAscii().toAsciiLower()
        if (token == "--no-open") {
            shouldOpen = false
            continue
        }
        if (token == "--open") {
            shouldOpen = true
            continue
        }
        if (token == "-h" || token == "--help" || token == "help") {
            PrintUtils.printLine("Usage: metis dashboard [--open|--no-open]")
            PrintUtils.printLine("Print the Control UI URL for the running gateway and optionally open it in your browser.")
            PrintUtils.printLine("The formal production path is static Control UI assets: bundled-root by default, or gateway.controlUi.root when explicitly configured. Inline fallback is legacy-only.")
            return 0
        }
        PrintUtils.printLine("Unknown dashboard option: ${arg}")
        PrintUtils.printLine("Usage: metis dashboard [--open|--no-open]")
        return 1
    }

    let (tokenSource, token) = gatewayDashboardResolveToken()
    let (assetMode, rootKind, rootMessage) = gatewayDashboardAssetModeSummary()
    let url = gatewayDashboardBuildUrl()
    PrintUtils.printLine("Dashboard URL: ${url}")
    if (assetMode == "static-root" || assetMode == "bundled-root") {
        PrintUtils.printLine("Control UI asset mode: ${assetMode} (${if (rootKind.isEmpty()) { "configured" } else { rootKind }})")
    } else {
        PrintUtils.printLine("Control UI asset mode: legacy inline fallback")
        PrintUtils.printLine("Recommendation: keep bundled static assets available, or set `gateway.controlUi.root` to a built static UI directory.")
    }
    if (!rootMessage.trimAscii().isEmpty()) {
        PrintUtils.printLine("Control UI root state: ${rootMessage}")
    }
    if (tokenSource == "config" && !token.isEmpty()) {
        PrintUtils.printLine("Token auto-auth source: config")
    } else if (tokenSource == "env" && !token.isEmpty()) {
        PrintUtils.printLine("Token auto-auth source: env (CANGJIECLAW_GATEWAY_TOKEN)")
    } else {
        PrintUtils.printLine("Token auto-auth unavailable: no gateway token configured")
    }
    if (gatewayDashboardTryCopy(url)) {
        PrintUtils.printLine("Copied to clipboard.")
    } else {
        PrintUtils.printLine("Copy to clipboard unavailable.")
    }
    if (!gatewayAnotherServeInstanceSeemsRunning()) {
        PrintUtils.printLine("Gateway does not appear to be running. Start it with `metis gateway run` and then reopen the URL above.")
        return 0
    }
    if (!shouldOpen) {
        PrintUtils.printLine("Browser launch disabled (--no-open). Use the URL above.")
        return 0
    }
    if (gatewayDashboardTryOpen(url)) {
        PrintUtils.printLine("Opened in your browser. Keep that tab connected to the gateway.")
    } else {
        PrintUtils.printLine(gatewayDashboardOpenHint(url))
    }
    0
}

/**
 * `gateway serve` 不经 `parseArgsAndSetConfig`，在此与 `~/.metis/metis.json` 对齐模型等配置。
 * 放在 `metis.gateway.runtime`，避免 `metis.core.config` 依赖 `metis.core.model` 产生环。
 */
private func applyRuntimeForGatewayServe(): Unit {
    // 与 parseArgsAndSetConfig 对齐：否则 LogUtils.info 可能不写文件或级别不对，~/.metis/logs 里看不到 Gateway.*。
    Config.logLevel = "INFO"
    Config.logFile = CliConfig.logFile.toString()
    Config.modelRequestDir = CliConfig.dotDir.join("model-requests").toString()
    Config.enableModelToolCall = true
    Config.enableParallelToolCall = false
    Config.httpReadWriteTimeout = 600000
    CliConfig.cleanupLogs()
    MetisConfigManager.initializeIfMissing()
    MetisConfigManager.applyPersistedFieldsToCliConfig()
    CliSettingManager.applyPersistedFieldsToCliConfig()
    // Gateway serve should not kick off heavy qmd boot indexing on startup.
    // Keep control-plane startup compact and do not rescan the whole workspace here.
    MemoryRuntimeRegistry.activateBackend(CliConfig.memoryProvider, startMaintenance: false)
    SkillsPrompt.invalidate()
    CliModelManager.resetRuntimeState()
}

private func runGatewayStopSubcommand(): Int64 {
    let startMs = gatewayCliNowMs()
    gatewayCliTimingLog("stop", "enter", startMs)
    let lockPath = gatewayServeLockPath()
    let listenerPids = gatewayFindVerifiedListenerPidsOnPort()
    let lockPid = gatewayPeekServeLockPid()
    let stopPids = gatewayResolveStopTargetPids(listenerPids, lockPid: lockPid)
    if (!exists(lockPath) && stopPids.isEmpty()) {
        gatewayRuntimeMarkStoppedFromCli(reason: "stopped")
        PrintUtils.printLine("[网关] 未发现 ~/.metis/gateway-serve.lock，可能没有正在运行的 gateway serve。")
        gatewayCliTimingLog("stop", "no-lock", startMs)
        return 0
    }
    let me = gatewayCliOwnProcessId()
    if (listenerPids.size > 0) {
        let listenerPidText = String.join(
            listenerPids |> map({p => p.toString()}) |> collectArray,
            delimiter: ","
        )
        match (lockPid) {
            case Some(pid) =>
                var matched = false
                for (listenerPid in listenerPids) {
                    if (listenerPid == pid) {
                        matched = true
                        break
                    }
                }
                if (!matched) {
                    PrintUtils.printLine(
                        "[网关] 检测到锁文件 PID=${pid} 与真实 listener PID=${listenerPidText} 不一致，将以 listener 为准。"
                    )
                }
            case None => ()
        }
    }
    for (pid in stopPids) {
        if (pid == me) {
            PrintUtils.printLine("[网关] 当前进程即为 gateway serve，请在本窗口按 Ctrl+C 退出；勿在同一进程执行 gateway stop。")
            gatewayCliTimingLog("stop", "self-process", startMs)
            return 1
        }
    }
    if (stopPids.isEmpty()) {
        gatewayReleaseServeLockQuiet()
        gatewayRuntimeMarkStoppedFromCli(reason: "stopped")
        PrintUtils.printLine("[网关] 已移除无 PID 的旧版锁。若仍有网关 CMD 窗口，请手动关闭。")
        gatewayCliTimingLog("stop", "legacy-lock-cleared", startMs)
        return 0
    }
    let stopPidText = String.join(
        stopPids |> map({p => p.toString()}) |> collectArray,
        delimiter: ","
    )
    PrintUtils.printLine("[网关] 正在停止 gateway serve（PID=${stopPidText}）…")
    gatewayCliTimingLog("stop", "terminate-begin", startMs)
    let failed = ArrayList<Int64>()
    for (pid in stopPids) {
        if (!gatewayServePidIsAlive(pid)) {
            continue
        }
        if (!gatewayTryTerminateServeProcess(pid)) {
            failed.add(pid)
        }
    }
    if (failed.isEmpty()) {
        gatewayReleaseServeLockQuiet()
        gatewayRuntimeMarkStoppedFromCli(reason: "stopped")
        PrintUtils.printLine("[网关] 已停止。")
        gatewayCliTimingLog("stop", "terminate-done", startMs)
        return 0
    }
    let failedPidText = String.join(
        failed.toArray() |> map({p => p.toString()}) |> collectArray,
        delimiter: ","
    )
    PrintUtils.printLine("[网关] 未能结束进程 PID=${failedPidText}，请手动关闭对应终端窗口或在任务管理器中结束进程。")
    gatewayCliTimingLog("stop", "terminate-failed", startMs)
    return 1
}

/** 与命令行 `gateway stop` 相同逻辑；供 `/Metis` 菜单等调用（依赖当前已初始化的 CliConfig）。 */
public func gatewayExecuteStopServe(): Int64 {
    runGatewayStopSubcommand()
}

/** 与命令行 `gateway restart` 相同逻辑。 */
public func gatewayExecuteRestartServe(): Int64 {
    let startMs = gatewayCliNowMs()
    gatewayCliTimingLog("restart", "enter", startMs)
    match (gatewayRestartConfigValidationMessage()) {
        case Some(message) =>
            PrintUtils.printLine(message)
            gatewayCliTimingLog("restart", "config-invalid", startMs)
            return 1
        case None => ()
    }
    let code = runGatewayStopSubcommand()
    if (code != 0) {
        gatewayCliTimingLog("restart", "stop-failed", startMs)
        return code
    }
    gatewayCliTimingLog("restart", "stop-done", startMs)
    PrintUtils.printLine("[网关] 正在另开窗口启动 gateway serve …")
    let launched = gatewayLaunchDedicatedConsole()
    gatewayCliTimingLog("restart", if (launched) { "launch-done" } else { "launch-failed" }, startMs)
    return if (launched) {
        0
    } else {
        1
    }
}

/**
 * 执行 `gateway` 子命令；返回进程退出码。
 */
public func runGatewayCli(sub: Array<String>): Int64 {
    applyRuntimeForGatewayServe()

    if (sub.size == 0 || sub[0] == "help" || sub[0] == "-h" || sub[0] == "--help") {
        printGatewayHelp()
        return 0
    }

    let cmd = sub[0]
    if (cmd == "run") {
        return gatewayRunForeground(flowName: "run")
    }
    if (cmd == "status") {
        gatewayActionsPrintStatus()
        return 0
    }
    if (cmd == "health") {
        gatewayPrintHealth()
        return 0
    }
    if (cmd == "probe") {
        gatewayPrintProbe()
        return 0
    }
    if (cmd == "discover") {
        gatewayPrintDiscover()
        return 0
    }
    if (cmd == "call") {
        return gatewayRunCallCli(sub)
    }
    if (cmd == "usage-cost") {
        gatewayPrintUsageCost()
        return 0
    }
    if (cmd == "master") {
        if (sub.size < 2) {
            PrintUtils.printLine("Usage: gateway master on|off")
            return 1
        }
        let sw = sub[1].trimAscii().toAsciiLower()
        if (sw == "on" || sw == "true" || sw == "1") {
            gatewayActionsSetMaster(true)
        } else if (sw == "off" || sw == "false" || sw == "0") {
            gatewayActionsSetMaster(false)
        } else {
            PrintUtils.printLine("Usage: gateway master on|off")
            return 1
        }
        return 0
    }
    if (cmd == "serve") {
        return gatewayRunForeground(flowName: "serve")
    }
    if (cmd == "stop") {
        return gatewayExecuteStopServe()
    }
    if (cmd == "restart") {
        return gatewayExecuteRestartServe()
    }
    if (cmd == "sessions") {
        return runGatewaySessionsCli(sub)
    }
    if (cmd == "subagents") {
        let commandLine = "/" + joinFrom(sub, 0)
        let (ok, answer, err) = gatewayInvokeCliAgent(commandLine, sessionKey: "main", channel: "cli")
        if (ok) {
            gatewayPrintCommandOutput(answer)
            return if (answer.contains("\"ok\":false")) { 1 } else { 0 }
        }
        PrintUtils.printLine("Gateway agent failed: ${err}")
        return 1
    }
    if (cmd == "cron") {
        return runGatewayCronCli(sub)
    }
    if (cmd == "media" && sub.size >= 2 && sub[1].trimAscii().toAsciiLower() == "image") {
        return gatewayRunMediaImageCli(sub)
    }
    if (cmd == "channel" || cmd == "channels") {
        return gatewayRunChannelCli(sub)
    }
    if (cmd == "plugin" || cmd == "plugins") {
        if (sub.size < 2 || sub[1] == "help" || sub[1] == "-h" || sub[1] == "--help") {
            gatewayPrintPluginHelp()
            return 0
        }
        let subcmd = sub[1].trimAscii().toAsciiLower()
        if (subcmd == "list") {
            gatewayActionsPrintPluginsList()
            return 0
        }
        if (subcmd == "list-supported") {
            return if (gatewayActionsPrintPluginSupportedChannels()) { 0 } else { 1 }
        }
        if (subcmd == "install") {
            if (sub.size < 3) {
                PrintUtils.printLine("Usage: gateway plugin install <name> [--app-id <id>] [--app-secret <secret>] [--force]")
                return 1
            }
            let name = sub[2]
            let (appId, appSecret, force, ok) = gatewayPluginParseInstallFlags(sub, 3)
            if (!ok) {
                PrintUtils.printLine("Usage: gateway plugin install <name> [--app-id <id>] [--app-secret <secret>] [--force]")
                return 1
            }
            return if (gatewayActionsInstallPlugin(name, appId: appId, appSecret: appSecret, force: force)) {
                0
            } else {
                1
            }
        }
        if (subcmd == "enable") {
            if (sub.size < 3) {
                PrintUtils.printLine("Usage: gateway plugin enable <id>")
                return 1
            }
            return if (gatewayActionsSetPluginEnabled(sub[2], true)) { 0 } else { 1 }
        }
        if (subcmd == "disable") {
            if (sub.size < 3) {
                PrintUtils.printLine("Usage: gateway plugin disable <id>")
                return 1
            }
            return if (gatewayActionsSetPluginEnabled(sub[2], false)) { 0 } else { 1 }
        }
        if (subcmd == "set") {
            if (sub.size < 5) {
                PrintUtils.printLine("Usage: gateway plugin set <id> <key> <value...>")
                return 1
            }
            let pid = sub[2]
            let key = sub[3]
            let value = joinFrom(sub, 4)
            return if (gatewayActionsSetPluginField(pid, key, value)) { 0 } else { 1 }
        }
        PrintUtils.printLine("Unknown gateway plugin subcommand: ${subcmd}")
        PrintUtils.printLine("Try: gateway plugin list")
        return 1
    }
    PrintUtils.printLine("Unknown gateway command: ${cmd}")
    PrintUtils.printLine("Try: metis gateway help")
    1
}
