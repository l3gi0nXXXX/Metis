package metis.program

import magic.utils.readFile
import magic.jsonable.*

import metis.cliapp.runEmbeddedPrompt
import metis.core.config.{CliConfig, MetisConfigManager, MetisPaths, CliSettingManager, cliFindModelProviderDescriptor, cliModelProviderCatalogDescriptors, cliValidateProviderBaseUrl}
import metis.core.mcp.{mcpConfiguredServerJson, mcpConfiguredServersJson, mcpConfiguredServersPath, mcpResolveSecretOption, mcpSetConfiguredServerJson, mcpUnsetConfiguredServerJson}
import metis.gateway.channels.telegram.telegramPairingAccountStore
import metis.gateway.security.{gatewayNormalizePairingAccountId, gatewayPairingAccountStore}
import metis.mcp.{MetisMcpServeOptions, serveMetisChannelMcp}
import metis.gateway.runtime.{gatewayCliClient, gatewayCliShouldPrintRuntimeRequiredHint, gatewayInvokeCliAgent, gatewayInvokeCliAgentResult}
import metis.io.PrintUtils
import metis.program_support.programSupportRenderLocalCommandSummary

import std.collection.ArrayList
import std.convert.*
import std.fs.exists
import std.fs.Path
import std.sort.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString, JsonValue}

private func firstArg(args: Array<String>): String {
    if (args.isEmpty()) {
        return ""
    }
    args[0].trimAscii().toAsciiLower()
}

private func argAt(args: Array<String>, index: Int64): String {
    if (index < 0 || index >= args.size) {
        return ""
    }
    args[index].trimAscii()
}

private func joinArgs(args: Array<String>, start!: Int64 = 0): String {
    if (start >= args.size) {
        return ""
    }
    let out = ArrayList<String>()
    for (idx in start..args.size) {
        out.add(args[idx])
    }
    String.join(out.toArray(), delimiter: " ").trimAscii()
}

private func printJsonObject(obj: JsonObject): Int64 {
    PrintUtils.printLine(obj.toJsonString())
    CLI_EXIT_OK
}

private func printJsonValue(value: JsonValue): Int64 {
    PrintUtils.printLine(value.toJsonString())
    CLI_EXIT_OK
}

private func localArgsWantJson(args: Array<String>): Bool {
    for (arg in args) {
        let low = arg.trimAscii().toAsciiLower()
        if (low == "--json" || low == "json") {
            return true
        }
    }
    false
}

private func localJsonString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(value) =>
            try { value.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func localJsonArraySummary(value: JsonValue): String {
    let arr = try {
        value.asArray()
    } catch (_e: Exception) {
        return ""
    }
    if (arr.size() == 0) {
        return "(none)"
    }
    let items = ArrayList<String>()
    var allStrings = true
    for (idx in 0..arr.size()) {
        try {
            items.add(arr[idx].asString().getValue())
        } catch (_e: Exception) {
            allStrings = false
        }
    }
    if (allStrings) {
        return String.join(items.toArray(), delimiter: ", ")
    }
    return "${arr.size()} item(s)"
}

private func localJsonScalarSummary(value: JsonValue): String {
    try {
        return value.asString().getValue()
    } catch (_e: Exception) {
        ()
    }
    try {
        return if (value.asBool().getValue()) { "true" } else { "false" }
    } catch (_e: Exception) {
        ()
    }
    try {
        return "${value.asInt().getValue()}"
    } catch (_e: Exception) {
        ()
    }
    let arrayText = localJsonArraySummary(value)
    if (!arrayText.isEmpty()) {
        return arrayText
    }
    return "available with --json"
}

private func localSummaryKnownField(key: String): Bool {
    key == "kind" ||
    key == "command" ||
    key == "subcommand" ||
    key == "status" ||
    key == "nextSteps" ||
    key == "modelConfig" ||
    key == "modelRuntime" ||
    key == "runtimeState" ||
    key == "modelSelection" ||
    key == "authChoices" ||
    key == "authChoiceGroups" ||
    key == "providers" ||
    key == "pending" ||
    key == "approvedSenders" ||
    key == "code"
}

private func localFieldLabel(key: String): String {
    if (key == "configPath") { return "Config path" }
    if (key == "logsDir") { return "Logs dir" }
    if (key == "storeRoot") { return "Store root" }
    if (key == "accountId") { return "Account" }
    if (key == "currentModel") { return "Current model" }
    if (key == "availableProviders") { return "Available providers" }
    if (key == "rootRemoval") { return "Would remove root" }
    if (key == "pendingCount") { return "Pending" }
    if (key == "approvedCount") { return "Approved senders" }
    if (key == "approved") { return "Approved" }
    if (key == "dispatchMode") { return "Dispatch mode" }
    if (key == "primaryPath") { return "Primary path" }
    return key
}

private func localAppendField(lines: ArrayList<String>, obj: JsonObject, key: String): Unit {
    match (obj.get(key)) {
        case Some(value) =>
            let text = localJsonScalarSummary(value)
            if (!text.isEmpty()) {
                lines.add("  ${localFieldLabel(key)}: ${text}")
            }
        case None => ()
    }
}

public func cliRenderLocalCommandSummary(obj: JsonObject): String {
    programSupportRenderLocalCommandSummary(obj)
}

private func printLocalCommandHuman(obj: JsonObject): Int64 {
    for (line in cliRenderLocalCommandSummary(obj).split("\n")) {
        PrintUtils.printLine(line)
    }
    CLI_EXIT_OK
}

private func localPrintCommandResult(args: Array<String>, obj: JsonObject): Int64 {
    if (localArgsWantJson(args)) {
        return printJsonObject(obj)
    }
    printLocalCommandHuman(obj)
}

private func localPrintMutationResult(args: Array<String>, obj: JsonObject, warning: String): Int64 {
    if (localArgsWantJson(args)) {
        return printJsonObject(obj)
    }
    PrintUtils.printLine("Warning: ${warning}")
    printLocalCommandHuman(obj)
}

public func cliGatewayShouldPrintRuntimeHintForError(error: String): Bool {
    let lower = error.toAsciiLower()
    if (lower.contains("already exists") ||
        lower.contains("not found") ||
        lower.contains("cannot be deleted") ||
        lower.contains("cannot be recreated") ||
        lower.contains("is a builtin agent") ||
        lower.contains("is required") ||
        lower.contains("invalid") ||
        lower.contains("duplicate") ||
        lower.contains("conflict")) {
        return false
    }
    true
}

private func printGatewayRpcFailure(scope: String, method: String, error: String): Int64 {
    PrintUtils.printLine("Gateway ${scope} failed: ${cliRedactTextForOutput(error)}")
    if (cliGatewayShouldPrintRuntimeHintForError(error)) {
        PrintUtils.printLine("Start the unified Gateway main runtime with `metis gateway run`, then retry `${method}`.")
    }
    CLI_EXIT_USAGE_ERROR
}

private func gatewayAgentsBuiltinRows(result: JsonObject): JsonArray {
    match (result.get("builtin")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func gatewayAgentsCustomRows(result: JsonObject): JsonArray {
    match (result.get("custom")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func gatewayAgentsResultCount(result: JsonObject): Int64 {
    Int64(gatewayAgentsBuiltinRows(result).size() + gatewayAgentsCustomRows(result).size())
}

private func gatewayAgentsJsonInt(obj: JsonObject, key: String, defaultValue: Int64): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            try { Int64.parse(v.toJsonString()) } catch (_e: Exception) { defaultValue }
        case None => defaultValue
    }
}

private func gatewayAgentsJsonString(obj: JsonObject, key: String, defaultValue: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { defaultValue }
        case None => defaultValue
    }
}

private func cliIsSecretOutputField(key: String): Bool {
    let low = key.trimAscii().toAsciiLower()
    low == "appsecret" ||
    low == "bottoken" ||
    low == "token" ||
    low == "apikey" ||
    low == "authorization" ||
    low.contains("secret") ||
    low.contains("token")
}

private func cliIsAppIdOutputField(key: String): Bool {
    key.trimAscii().toAsciiLower() == "appid"
}

public func cliRedactCredentialFieldForOutput(key: String, value: String): String {
    let clean = value.trimAscii()
    if (clean.isEmpty()) {
        return ""
    }
    if (cliIsSecretOutputField(key)) {
        return "[redacted]"
    }
    if (cliIsAppIdOutputField(key)) {
        return if (clean.size >= 4) { "${clean[..4]}..." } else { "[set]" }
    }
    clean
}

private func cliRedactJsonValueForOutput(value: JsonValue, key!: String = ""): JsonValue {
    if (cliIsSecretOutputField(key) || cliIsAppIdOutputField(key)) {
        let text = try { value.asString().getValue() } catch (_e: Exception) { value.toJsonString() }
        return JsonString(cliRedactCredentialFieldForOutput(key, text))
    }
    try {
        let obj = value.asObject()
        let out = JsonObject()
        for ((field, nested) in obj.getFields()) {
            out.put(field, cliRedactJsonValueForOutput(nested, key: field))
        }
        return out
    } catch (_e: Exception) {
        ()
    }
    try {
        let arr = value.asArray()
        let out = ArrayList<JsonValue>()
        for (idx in 0..arr.size()) {
            out.add(cliRedactJsonValueForOutput(arr[idx]))
        }
        return JsonArray(out)
    } catch (_e: Exception) {
        ()
    }
    value
}

public func cliRedactJsonObjectForOutput(obj: JsonObject): JsonObject {
    let out = JsonObject()
    for ((field, nested) in obj.getFields()) {
        out.put(field, cliRedactJsonValueForOutput(nested, key: field))
    }
    out
}

private func cliRedactTextAfterPattern(text: String, pattern: String): String {
    let idx = match (text.indexOf(pattern)) {
        case Some(v) => v
        case None => return text
    }
    let start = idx + pattern.size
    let rest = text[start..]
    var end = rest.size
    for (separator in [" ", "\n", "\t", ",", ";", ")"]) {
        match (rest.indexOf(separator)) {
            case Some(v) =>
                if (v < end) { end = v }
            case None => ()
        }
    }
    text[..start] + "[redacted]" + rest[end..]
}

public func cliRedactTextForOutput(text: String): String {
    var out = text
    for (pattern in ["appSecret=", "appSecret:", "botToken=", "botToken:", "token=", "token:", "secret=", "secret:", "Authorization:"]) {
        var next = cliRedactTextAfterPattern(out, pattern)
        while (next != out) {
            out = next
            next = cliRedactTextAfterPattern(out, pattern)
        }
    }
    out
}

public class CliAgentsTeamRpcSpec {
    public let method: String
    public let params: JsonObject
    public let json: Bool
    public let action: String

    public init(method: String, params: JsonObject, json: Bool, action: String) {
        this.method = method
        this.params = params
        this.json = json
        this.action = action
    }
}

public class CliAgentsMigrationRpcSpec {
    public let method: String
    public let params: JsonObject
    public let json: Bool
    public let action: String

    public init(method: String, params: JsonObject, json: Bool, action: String) {
        this.method = method
        this.params = params
        this.json = json
        this.action = action
    }
}

public class CliAgentsAddRpcSpec {
    public let method: String
    public let params: JsonObject
    public let json: Bool

    public init(method: String, params: JsonObject, json: Bool) {
        this.method = method
        this.params = params
        this.json = json
    }
}

private class CliAgentsUpdateParseResult {
    public let spec: Option<CliAgentsAddRpcSpec>
    public let missing: String
    public let invalid: String

    public init(spec: Option<CliAgentsAddRpcSpec>, missing: String, invalid: String) {
        this.spec = spec
        this.missing = missing
        this.invalid = invalid
    }
}

private class CliAgentsAddParseResult {
    public let spec: Option<CliAgentsAddRpcSpec>
    public let missing: String
    public let invalid: String

    public init(spec: Option<CliAgentsAddRpcSpec>, missing: String, invalid: String) {
        this.spec = spec
        this.missing = missing
        this.invalid = invalid
    }
}

private class CliAgentsCredentialPair {
    public let appId: String
    public let appSecret: String

    public init(appId: String, appSecret: String) {
        this.appId = appId
        this.appSecret = appSecret
    }
}

private func cliAgentsParseCredentialPair(raw: String): Option<CliAgentsCredentialPair> {
    let value = raw.trimAscii()
    if (value.isEmpty()) {
        return None<CliAgentsCredentialPair>
    }
    let pivot = match (value.indexOf(":")) {
        case Some(v) => v
        case None => return None<CliAgentsCredentialPair>
    }
    if (pivot <= 0 || pivot >= value.size - 1) {
        return None<CliAgentsCredentialPair>
    }
    let appId = value[..pivot].trimAscii()
    let appSecret = value[pivot + 1..].trimAscii()
    if (appId.isEmpty() || appSecret.isEmpty()) {
        return None<CliAgentsCredentialPair>
    }
    Some(CliAgentsCredentialPair(appId, appSecret))
}

private func cliAgentsAddCredentialObject(accountId: String, pair: CliAgentsCredentialPair): JsonObject {
    let obj = JsonObject()
    obj.put("accountId", JsonString(accountId))
    obj.put("appId", JsonString(pair.appId))
    obj.put("appSecret", JsonString(pair.appSecret))
    obj
}

private func cliAgentsAddTelegramCredentialObject(accountId: String, botToken: String): JsonObject {
    let obj = JsonObject()
    obj.put("accountId", JsonString(accountId))
    obj.put("botToken", JsonString(botToken))
    obj
}

private func cliAgentsAddPushBinding(out: ArrayList<JsonValue>, seen: ArrayList<String>, raw: String): Unit {
    let value = raw.trimAscii()
    if (value.isEmpty() || seen.contains(value)) {
        return
    }
    seen.add(value)
    out.add(JsonString(value))
}

private func cliParseAgentsAddRpcSpec(args: Array<String>): CliAgentsAddParseResult {
    if (args.size < 1 || args[0].trimAscii().toAsciiLower() != "add") {
        return CliAgentsAddParseResult(None<CliAgentsAddRpcSpec>, "", "add")
    }
    var json = false
    var agentId = ""
    var name = ""
    var workspace = ""
    var model = ""
    let explicitBinds = ArrayList<String>()
    var feishuRaw = ""
    var feishuAccount = ""
    var qqRaw = ""
    var qqAccount = ""
    var telegramToken = ""
    var telegramAccount = ""
    var channelOverwrite = false
    var i: Int64 = 1
    while (i < args.size) {
        let token = args[i].trimAscii()
        let low = token.toAsciiLower()
        if (low == "--json") {
            json = true
            i += 1
            continue
        }
        if (low == "--channel-overwrite") {
            channelOverwrite = true
            i += 1
            continue
        }
        if (low == "--agent") {
            if (i + 1 >= args.size) { return CliAgentsAddParseResult(None<CliAgentsAddRpcSpec>, "--agent <id>", "") }
            agentId = args[i + 1].trimAscii()
            i += 2
            continue
        }
        if (low == "--name") {
            if (i + 1 >= args.size) { return CliAgentsAddParseResult(None<CliAgentsAddRpcSpec>, "--name <text>", "") }
            name = args[i + 1]
            i += 2
            continue
        }
        if (low == "--workspace") {
            if (i + 1 >= args.size) { return CliAgentsAddParseResult(None<CliAgentsAddRpcSpec>, "--workspace <path>", "") }
            workspace = args[i + 1].trimAscii()
            i += 2
            continue
        }
        if (low == "--model") {
            if (i + 1 >= args.size) { return CliAgentsAddParseResult(None<CliAgentsAddRpcSpec>, "--model <ref>", "") }
            model = args[i + 1].trimAscii()
            i += 2
            continue
        }
        if (low == "--bind") {
            if (i + 1 >= args.size) { return CliAgentsAddParseResult(None<CliAgentsAddRpcSpec>, "--bind <channel[:account]>", "") }
            explicitBinds.add(args[i + 1].trimAscii())
            i += 2
            continue
        }
        if (low == "--feishu") {
            if (i + 1 >= args.size) { return CliAgentsAddParseResult(None<CliAgentsAddRpcSpec>, "--feishu <appId:appSecret>", "") }
            feishuRaw = args[i + 1].trimAscii()
            i += 2
            continue
        }
        if (low == "--feishu-account") {
            if (i + 1 >= args.size) { return CliAgentsAddParseResult(None<CliAgentsAddRpcSpec>, "--feishu-account <id>", "") }
            feishuAccount = args[i + 1].trimAscii()
            i += 2
            continue
        }
        if (low == "--qqbot") {
            if (i + 1 >= args.size) { return CliAgentsAddParseResult(None<CliAgentsAddRpcSpec>, "--qqbot <appId:appSecret>", "") }
            qqRaw = args[i + 1].trimAscii()
            i += 2
            continue
        }
        if (low == "--qqbot-account") {
            if (i + 1 >= args.size) { return CliAgentsAddParseResult(None<CliAgentsAddRpcSpec>, "--qqbot-account <id>", "") }
            qqAccount = args[i + 1].trimAscii()
            i += 2
            continue
        }
        if (low == "--telegram" || low == "--telegram-bot-token") {
            if (i + 1 >= args.size) { return CliAgentsAddParseResult(None<CliAgentsAddRpcSpec>, "${low} <token>", "") }
            let nextToken = args[i + 1].trimAscii()
            if (!telegramToken.isEmpty() && telegramToken != nextToken) {
                return CliAgentsAddParseResult(None<CliAgentsAddRpcSpec>, "", "telegram token flags must agree")
            }
            telegramToken = nextToken
            i += 2
            continue
        }
        if (low == "--telegram-account") {
            if (i + 1 >= args.size) { return CliAgentsAddParseResult(None<CliAgentsAddRpcSpec>, "--telegram-account <id>", "") }
            telegramAccount = args[i + 1].trimAscii()
            i += 2
            continue
        }
        return CliAgentsAddParseResult(None<CliAgentsAddRpcSpec>, "", token)
    }
    if (agentId.isEmpty()) {
        return CliAgentsAddParseResult(None<CliAgentsAddRpcSpec>, "--agent <id>", "")
    }
    let params = JsonObject()
    params.put("agentId", JsonString(agentId))
    if (!name.trimAscii().isEmpty()) { params.put("name", JsonString(name.trimAscii())) }
    if (!workspace.trimAscii().isEmpty()) { params.put("workspace", JsonString(workspace)) }
    if (!model.trimAscii().isEmpty()) { params.put("model", JsonString(model.trimAscii())) }

    let binds = ArrayList<JsonValue>()
    let seenBinds = ArrayList<String>()
    for (item in explicitBinds) {
        cliAgentsAddPushBinding(binds, seenBinds, item)
    }

    let credentials = JsonObject()
    var hasCredential = false
    if (!feishuRaw.isEmpty()) {
        let pair = match (cliAgentsParseCredentialPair(feishuRaw)) {
            case Some(v) => v
            case None => return CliAgentsAddParseResult(None<CliAgentsAddRpcSpec>, "", "--feishu expects appId:appSecret")
        }
        let account = if (feishuAccount.isEmpty()) { agentId } else { feishuAccount }
        credentials.put("feishu", cliAgentsAddCredentialObject(account, pair))
        cliAgentsAddPushBinding(binds, seenBinds, "feishu:${account}")
        hasCredential = true
    }
    if (!qqRaw.isEmpty()) {
        let pair = match (cliAgentsParseCredentialPair(qqRaw)) {
            case Some(v) => v
            case None => return CliAgentsAddParseResult(None<CliAgentsAddRpcSpec>, "", "--qqbot expects appId:appSecret")
        }
        let account = if (qqAccount.isEmpty()) { agentId } else { qqAccount }
        credentials.put("qq", cliAgentsAddCredentialObject(account, pair))
        cliAgentsAddPushBinding(binds, seenBinds, "qq:${account}")
        hasCredential = true
    }
    if (!telegramToken.isEmpty()) {
        let account = if (telegramAccount.isEmpty()) { agentId } else { telegramAccount }
        credentials.put("telegram", cliAgentsAddTelegramCredentialObject(account, telegramToken))
        cliAgentsAddPushBinding(binds, seenBinds, "telegram:${account}")
        hasCredential = true
    }
    if (binds.size > 0) {
        params.put("bind", JsonArray(binds))
    }
    if (hasCredential) {
        params.put("channelCredentials", credentials)
        params.put("channelOverwrite", JsonBool(channelOverwrite))
    } else if (channelOverwrite) {
        params.put("channelOverwrite", JsonBool(true))
    }
    CliAgentsAddParseResult(Some(CliAgentsAddRpcSpec("agents.add", params, json)), "", "")
}

public func cliBuildAgentsAddRpcSpec(args: Array<String>): Option<CliAgentsAddRpcSpec> {
    cliParseAgentsAddRpcSpec(args).spec
}

private func cliParseAgentsUpdateRpcSpec(args: Array<String>): CliAgentsUpdateParseResult {
    if (args.size < 1 || args[0].trimAscii().toAsciiLower() != "update") {
        return CliAgentsUpdateParseResult(None<CliAgentsAddRpcSpec>, "", "update")
    }
    var json = false
    var agentId = ""
    var name = ""
    var workspace = ""
    var model = ""
    var i: Int64 = 1
    while (i < args.size) {
        let token = args[i].trimAscii()
        let low = token.toAsciiLower()
        if (low == "--json") {
            json = true
            i += 1
            continue
        }
        if (low == "--agent") {
            if (i + 1 >= args.size) { return CliAgentsUpdateParseResult(None<CliAgentsAddRpcSpec>, "--agent <id>", "") }
            agentId = args[i + 1].trimAscii()
            i += 2
            continue
        }
        if (low == "--name") {
            if (i + 1 >= args.size) { return CliAgentsUpdateParseResult(None<CliAgentsAddRpcSpec>, "--name <text>", "") }
            name = args[i + 1].trimAscii()
            i += 2
            continue
        }
        if (low == "--workspace") {
            if (i + 1 >= args.size) { return CliAgentsUpdateParseResult(None<CliAgentsAddRpcSpec>, "--workspace <path>", "") }
            workspace = args[i + 1].trimAscii()
            i += 2
            continue
        }
        if (low == "--model") {
            if (i + 1 >= args.size) { return CliAgentsUpdateParseResult(None<CliAgentsAddRpcSpec>, "--model <ref>", "") }
            model = args[i + 1].trimAscii()
            i += 2
            continue
        }
        return CliAgentsUpdateParseResult(None<CliAgentsAddRpcSpec>, "", token)
    }
    if (agentId.isEmpty()) {
        return CliAgentsUpdateParseResult(None<CliAgentsAddRpcSpec>, "--agent <id>", "")
    }
    if (name.isEmpty() && workspace.isEmpty() && model.isEmpty()) {
        return CliAgentsUpdateParseResult(None<CliAgentsAddRpcSpec>, "--model/--name/--workspace", "")
    }
    let params = JsonObject()
    params.put("agentId", JsonString(agentId))
    if (!name.isEmpty()) { params.put("name", JsonString(name)) }
    if (!workspace.isEmpty()) { params.put("workspace", JsonString(workspace)) }
    if (!model.isEmpty()) { params.put("model", JsonString(model)) }
    CliAgentsUpdateParseResult(Some(CliAgentsAddRpcSpec("agents.update", params, json)), "", "")
}

public func cliBuildAgentsUpdateRpcSpec(args: Array<String>): Option<CliAgentsAddRpcSpec> {
    cliParseAgentsUpdateRpcSpec(args).spec
}

private func cliAgentsJsonObjectFromText(raw: String): Option<JsonObject> {
    try {
        return Some(JsonValue.fromStr(raw).asObject())
    } catch (_: Exception) {
        return None<JsonObject>
    }
}

private func cliAgentsMigrationPutConfigRoot(params: JsonObject, raw: String): Bool {
    match (cliAgentsJsonObjectFromText(raw)) {
        case Some(obj) =>
            params.put("configRoot", obj)
            true
        case None => false
    }
}

private func cliAgentsMigrationAddBinding(bindings: ArrayList<JsonValue>, raw: String): Bool {
    match (cliAgentsJsonObjectFromText(raw)) {
        case Some(obj) =>
            bindings.add(obj)
            true
        case None => false
    }
}

public func cliBuildAgentsMigrationRpcSpec(args: Array<String>): Option<CliAgentsMigrationRpcSpec> {
    if (args.size < 1 || args[0].trimAscii().toAsciiLower() != "migrate") {
        return None<CliAgentsMigrationRpcSpec>
    }
    var json = false
    var dryRun = false
    let params = JsonObject()
    let proposedBindings = ArrayList<JsonValue>()
    var i: Int64 = 1
    while (i < args.size) {
        let token = args[i].trimAscii()
        let low = token.toAsciiLower()
        if (low == "--json") {
            json = true
            i += 1
            continue
        }
        if (low == "--dry-run" || low == "dry-run") {
            dryRun = true
            i += 1
            continue
        }
        if (low == "--config-json") {
            if (i + 1 >= args.size || !cliAgentsMigrationPutConfigRoot(params, args[i + 1])) {
                return None<CliAgentsMigrationRpcSpec>
            }
            i += 2
            continue
        }
        if (low == "--config" || low == "--config-file") {
            if (i + 1 >= args.size) {
                return None<CliAgentsMigrationRpcSpec>
            }
            try {
                if (!cliAgentsMigrationPutConfigRoot(params, readFile(Path(args[i + 1].trimAscii())))) {
                    return None<CliAgentsMigrationRpcSpec>
                }
            } catch (_: Exception) {
                return None<CliAgentsMigrationRpcSpec>
            }
            i += 2
            continue
        }
        if (low == "--binding-json" || low == "--proposed-binding") {
            if (i + 1 >= args.size || !cliAgentsMigrationAddBinding(proposedBindings, args[i + 1])) {
                return None<CliAgentsMigrationRpcSpec>
            }
            i += 2
            continue
        }
        return None<CliAgentsMigrationRpcSpec>
    }
    if (!dryRun) {
        return None<CliAgentsMigrationRpcSpec>
    }
    if (proposedBindings.size > 0) {
        params.put("proposedBindings", JsonArray(proposedBindings))
    }
    Some(CliAgentsMigrationRpcSpec("agents.migration.dryRun", params, json, "dry-run"))
}

private func cliAgentsTeamMemberParam(raw: String): JsonObject {
    let parts = raw.split(":")
    let obj = JsonObject()
    if (parts.size > 0) {
        obj.put("agentId", JsonString(parts[0].trimAscii()))
    }
    if (parts.size > 1 && !parts[1].trimAscii().isEmpty()) {
        obj.put("role", JsonString(parts[1].trimAscii()))
    }
    if (parts.size > 2 && !parts[2].trimAscii().isEmpty()) {
        obj.put("displayName", JsonString(parts[2].trimAscii()))
    }
    obj
}

private func cliAgentsTeamAliasParam(raw: String): JsonObject {
    let parts = raw.split("=")
    let obj = JsonObject()
    if (parts.size > 0) {
        obj.put("alias", JsonString(parts[0].trimAscii()))
    }
    if (parts.size > 1) {
        obj.put("agentId", JsonString(parts[1].trimAscii()))
    }
    obj
}

public func cliBuildAgentsTeamRpcSpec(args: Array<String>): Option<CliAgentsTeamRpcSpec> {
    if (args.size < 2 || args[0].trimAscii().toAsciiLower() != "team") {
        return None<CliAgentsTeamRpcSpec>
    }
    let action = args[1].trimAscii().toAsciiLower()
    var method = ""
    if (action == "list") { method = "agents.teams.list" }
    if (action == "get") { method = "agents.teams.get" }
    if (action == "create") { method = "agents.teams.create" }
    if (action == "update") { method = "agents.teams.update" }
    if (action == "delete") { method = "agents.teams.delete" }
    if (method.isEmpty()) {
        return None<CliAgentsTeamRpcSpec>
    }

    var json = false
    var teamId = ""
    var name = ""
    var template = ""
    let members = ArrayList<JsonValue>()
    let aliases = ArrayList<JsonValue>()
    let bindings = ArrayList<JsonValue>()
    var i: Int64 = 2
    while (i < args.size) {
        let token = args[i].trimAscii()
        let low = token.toAsciiLower()
        if (low == "--json") {
            json = true
            i += 1
            continue
        }
        if (low == "--team") {
            if (i + 1 >= args.size) { return None<CliAgentsTeamRpcSpec> }
            teamId = args[i + 1].trimAscii()
            i += 2
            continue
        }
        if (low == "--name") {
            if (i + 1 >= args.size) { return None<CliAgentsTeamRpcSpec> }
            name = args[i + 1].trimAscii()
            i += 2
            continue
        }
        if (low == "--template") {
            if (i + 1 >= args.size) { return None<CliAgentsTeamRpcSpec> }
            template = args[i + 1].trimAscii()
            i += 2
            continue
        }
        if (low == "--member") {
            if (i + 1 >= args.size) { return None<CliAgentsTeamRpcSpec> }
            members.add(cliAgentsTeamMemberParam(args[i + 1]))
            i += 2
            continue
        }
        if (low == "--alias") {
            if (i + 1 >= args.size) { return None<CliAgentsTeamRpcSpec> }
            aliases.add(cliAgentsTeamAliasParam(args[i + 1]))
            i += 2
            continue
        }
        if (low == "--binding-json" || low == "--binding") {
            if (i + 1 >= args.size) { return None<CliAgentsTeamRpcSpec> }
            match (cliAgentsJsonObjectFromText(args[i + 1])) {
                case Some(obj) => bindings.add(obj)
                case None => return None<CliAgentsTeamRpcSpec>
            }
            i += 2
            continue
        }
        if (low == "--bind") {
            if (i + 1 >= args.size) { return None<CliAgentsTeamRpcSpec> }
            bindings.add(JsonString(args[i + 1].trimAscii()))
            i += 2
            continue
        }
        return None<CliAgentsTeamRpcSpec>
    }

    let params = JsonObject()
    if (!teamId.isEmpty()) { params.put("id", JsonString(teamId)) }
    if (!name.isEmpty()) { params.put("displayName", JsonString(name)) }
    if (!template.isEmpty()) { params.put("template", JsonString(template)) }
    if (members.size > 0) { params.put("members", JsonArray(members)) }
    if (aliases.size > 0) { params.put("aliases", JsonArray(aliases)) }
    if (bindings.size > 0) { params.put("bindings", JsonArray(bindings)) }
    Some(CliAgentsTeamRpcSpec(method, params, json, action))
}

private func gatewayAgentsJsonArray(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func gatewayAgentsTeamValueSummary(value: JsonValue): String {
    try {
        return value.asString().getValue()
    } catch (_e: Exception) {
        ()
    }
    let obj = try {
        value.asObject()
    } catch (_e: Exception) {
        return "structured value"
    }
    let alias = gatewayAgentsJsonString(obj, "alias", "")
    let agentId = gatewayAgentsJsonString(obj, "agentId", "")
    if (!alias.isEmpty() && !agentId.isEmpty()) {
        return "${alias}=${agentId}"
    }
    let role = gatewayAgentsJsonString(obj, "role", "")
    let displayName = gatewayAgentsJsonString(obj, "displayName", "")
    var text = agentId
    if (!role.isEmpty()) { text += ":${role}" }
    if (!displayName.isEmpty()) { text += " (${displayName})" }
    if (!text.isEmpty()) {
        return text
    }
    "structured object"
}

private func gatewayAgentsTeamArraySummary(arr: JsonArray): String {
    if (arr.size() == 0) {
        return "(none)"
    }
    let out = ArrayList<String>()
    for (idx in 0..arr.size()) {
        out.add(gatewayAgentsTeamValueSummary(arr[idx]))
    }
    String.join(out.toArray(), delimiter: ", ")
}

private func printGatewayAgentTeam(team: JsonObject): Unit {
    let id = gatewayAgentsJsonString(team, "id", gatewayAgentsJsonString(team, "teamId", ""))
    let displayName = gatewayAgentsJsonString(team, "displayName", gatewayAgentsJsonString(team, "name", ""))
    PrintUtils.printLine("  - team id: ${id}")
    PrintUtils.printLine("    displayName: ${displayName}")
    PrintUtils.printLine("    defaultAgentId: ${gatewayAgentsJsonString(team, "defaultAgentId", "")}")
    PrintUtils.printLine("    members: ${gatewayAgentsTeamArraySummary(gatewayAgentsJsonArray(team, "members"))}")
    PrintUtils.printLine("    aliases: ${gatewayAgentsTeamArraySummary(gatewayAgentsJsonArray(team, "aliases"))}")
}

private func printGatewayAgentTeamResult(action: String, result: JsonObject): Int64 {
    if (action == "list") {
        let teams = gatewayAgentsJsonArray(result, "teams")
        PrintUtils.printLine("Agent teams: ${teams.size()}")
        for (idx in 0..teams.size()) {
            let team = try { teams[idx].asObject() } catch (_e: Exception) { JsonObject() }
            printGatewayAgentTeam(team)
        }
        return CLI_EXIT_OK
    }
    let team = match (result.get("team")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { result }
        case None => result
    }
    if (action == "delete") {
        PrintUtils.printLine("Deleted agent team:")
    } else if (action == "create") {
        PrintUtils.printLine("Created agent team:")
    } else if (action == "update") {
        PrintUtils.printLine("Updated agent team:")
    } else {
        PrintUtils.printLine("Agent team:")
    }
    printGatewayAgentTeam(team)
    CLI_EXIT_OK
}

func cliAgentsTeamHasAnyUpdateField(params: JsonObject): Bool {
    match (params.get("displayName")) { case Some(_) => return true case None => () }
    match (params.get("members")) { case Some(_) => return true case None => () }
    match (params.get("aliases")) { case Some(_) => return true case None => () }
    match (params.get("bindings")) { case Some(_) => return true case None => () }
    false
}

public func cliAgentsTeamProductSemanticsHelpText(): String {
    "Team CRUD is handled by CLI/UI/Gateway RPC. CRUD methods: list|get|create|update|delete. JSON responses include semantics.crudSurface=cli-ui-gateway-rpc and semantics.imSurface=runtime-route-alias-native-command. Telegram/Feishu IM are runtime entry points for route bindings, aliases, and native commands (runtime route/native command only); they do not create/update/delete teams. Team route means one deterministic agent, broadcast means explicit fan-out, delete preserves member agents/workspaces, and manager is a normal member/defaultAgent, not an autonomous manager runtime."
}

private func cliAgentAddBindingArray(result: JsonObject, key: String): JsonArray {
    let bindings = match (result.get("bindings")) {
        case Some(v) =>
            try { v.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let nested = gatewayAgentsJsonArray(bindings, key)
    if (nested.size() > 0) {
        return nested
    }
    gatewayAgentsJsonArray(result, key)
}

private func cliAppendAgentAddBindingLines(lines: ArrayList<String>, title: String, rows: JsonArray): Unit {
    if (rows.size() == 0) {
        return
    }
    lines.add(title)
    for (idx in 0..rows.size()) {
        try {
            lines.add("  - ${rows[idx].asString().getValue()}")
        } catch (_e: Exception) {
            let row = try { rows[idx].asObject() } catch (_: Exception) { JsonObject() }
            let binding = gatewayAgentsJsonString(row, "binding", "")
            let existing = gatewayAgentsJsonString(row, "existingAgentId", "")
            if (!binding.isEmpty() && !existing.isEmpty()) {
                lines.add("  - ${binding} (agent=${existing})")
            } else if (!binding.isEmpty()) {
                lines.add("  - ${binding}")
            }
        }
    }
}

public func cliRenderGatewayAgentAddResult(result: JsonObject, fallbackAgentId: String): String {
    let safe = cliRedactJsonObjectForOutput(result)
    let lines = ArrayList<String>()
    lines.add("Added agent: ${gatewayAgentsJsonString(safe, "agentId", fallbackAgentId)}")
    let name = gatewayAgentsJsonString(safe, "name", "")
    if (!name.isEmpty()) { lines.add("  name: ${name}") }
    let model = gatewayAgentsJsonString(safe, "model", "")
    if (!model.isEmpty()) { lines.add("  model: ${model}") }
    let workspace = gatewayAgentsJsonString(safe, "workspace", "")
    if (!workspace.isEmpty()) { lines.add("  workspace: ${workspace}") }
    let agentDir = gatewayAgentsJsonString(safe, "agentDir", "")
    if (!agentDir.isEmpty()) { lines.add("  agentDir: ${agentDir}") }
    let accounts = gatewayAgentsJsonArray(safe, "channelAccounts")
    if (accounts.size() > 0) {
        lines.add("Configured channel accounts:")
        for (idx in 0..accounts.size()) {
            let row = try { accounts[idx].asObject() } catch (_: Exception) { JsonObject() }
            let channel = gatewayAgentsJsonString(row, "channel", "")
            let accountId = gatewayAgentsJsonString(row, "accountId", "")
            let action = gatewayAgentsJsonString(row, "action", "")
            var line = "  - ${channel}:${accountId}"
            if (channel == "telegram") {
                let token = gatewayAgentsJsonString(row, "token", gatewayAgentsJsonString(row, "botToken", ""))
                if (!token.isEmpty()) { line += " token=${token}" }
            } else {
                let appId = gatewayAgentsJsonString(row, "appId", "")
                let appSecret = gatewayAgentsJsonString(row, "appSecret", "")
                if (!appId.isEmpty()) { line += " appId=${appId}" }
                if (!appSecret.isEmpty()) { line += " appSecret=${appSecret}" }
            }
            if (!action.isEmpty()) { line += " ${action}" }
            lines.add(line)
        }
    }
    cliAppendAgentAddBindingLines(lines, "Added bindings:", cliAgentAddBindingArray(safe, "added"))
    cliAppendAgentAddBindingLines(lines, "Skipped bindings:", cliAgentAddBindingArray(safe, "skipped"))
    cliAppendAgentAddBindingLines(lines, "Conflicts:", cliAgentAddBindingArray(safe, "conflicts"))
    String.join(lines.toArray(), delimiter: "\n")
}

public func cliRenderGatewayAgentUpdateResult(result: JsonObject, fallbackAgentId: String): String {
    let safe = cliRedactJsonObjectForOutput(result)
    let lines = ArrayList<String>()
    lines.add("Updated agent: ${gatewayAgentsJsonString(safe, "agentId", fallbackAgentId)}")
    let agent = match (safe.get("agent")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let name = gatewayAgentsJsonString(agent, "name", "")
    if (!name.isEmpty()) { lines.add("  name: ${name}") }
    let model = gatewayAgentsJsonString(agent, "model", "")
    if (!model.isEmpty()) { lines.add("  model: ${model}") }
    let workspace = gatewayAgentsJsonString(agent, "workspace", "")
    if (!workspace.isEmpty()) { lines.add("  workspace: ${workspace}") }
    let refresh = match (safe.get("modelsRefresh")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    if (refresh.size() > 0) {
        let ok = match (refresh.get("ok")) {
            case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { true }
            case None => true
        }
        lines.add("  modelsRefresh: ${if (ok) { "ok" } else { "failed" }}")
    }
    String.join(lines.toArray(), delimiter: "\n")
}

private func cliRunAgentsAddFlow(args: Array<String>): Int64 {
    let parsed = cliParseAgentsAddRpcSpec(args)
    match (parsed.spec) {
        case Some(spec) =>
            let res = gatewayCliClient().call(spec.method, params: spec.params)
            if (!res.ok) {
                return printGatewayRpcFailure("agents", "metis agents add", res.error)
            }
            if (spec.json) {
                return printJsonObject(cliRedactJsonObjectForOutput(res.toJson()))
            }
            let result = try {
                res.result.asObject()
            } catch (_e: Exception) {
                JsonObject()
            }
            PrintUtils.printLine(cliRenderGatewayAgentAddResult(result, gatewayAgentsJsonString(spec.params, "agentId", "")))
            CLI_EXIT_OK
        case None =>
            if (!parsed.missing.isEmpty()) {
                return cliReturnMissingArgument("agents", "add", parsed.missing)
            }
            cliReturnInvalidArgument("agents", "add", parsed.invalid, "--json | --agent <id> | --name <text> | --workspace <path> | --model <ref> | --bind <channel[:account]> | --feishu <appId:appSecret> | --feishu-account <id> | --qqbot <appId:appSecret> | --qqbot-account <id> | --telegram-bot-token <token> | --telegram-account <id> | --channel-overwrite")
    }
}

private func cliRunAgentsUpdateFlow(args: Array<String>): Int64 {
    let parsed = cliParseAgentsUpdateRpcSpec(args)
    match (parsed.spec) {
        case Some(spec) =>
            let res = gatewayCliClient().call(spec.method, params: spec.params)
            if (!res.ok) {
                return printGatewayRpcFailure("agents", "metis agents update", res.error)
            }
            if (spec.json) {
                return printJsonObject(cliRedactJsonObjectForOutput(res.toJson()))
            }
            let result = try {
                res.result.asObject()
            } catch (_e: Exception) {
                JsonObject()
            }
            PrintUtils.printLine(cliRenderGatewayAgentUpdateResult(result, gatewayAgentsJsonString(spec.params, "agentId", "")))
            CLI_EXIT_OK
        case None =>
            if (!parsed.missing.isEmpty()) {
                return cliReturnMissingArgument("agents", "update", parsed.missing)
            }
            cliReturnInvalidArgument("agents", "update", parsed.invalid, "--json | --agent <id> | --model <ref> | --name <text> | --workspace <path>")
    }
}

private func cliRunAgentsTeamFlow(args: Array<String>): Int64 {
    let action = if (args.size > 1) { args[1].trimAscii().toAsciiLower() } else { "" }
    if (action.isEmpty() || action == "help") {
        return printLocalFlowUsage(
            "agents team",
            "Manage AgentTeam definitions through CLI/UI/Gateway RPC. CRUD methods: list|get|create|update|delete. JSON output includes team semantics. Telegram/Feishu IM only trigger runtime routes, aliases, and native commands; they do not perform team CRUD. Manager is a normal member/defaultAgent, not an autonomous manager runtime.",
            [
                "metis agents team list",
                "metis agents team get --team content",
                "metis agents team create --team content --template pm-writer-reviewer",
                "metis agents team update --team content --name Editorial --member content-writer:writer:Writer",
                "metis agents team delete --team content",
                "metis agents team list --json"
            ],
            "list [--json] | get --team <id> [--json] | create --team <id> [--name <displayName>] [--template pm-writer-reviewer] [--member <agentId[:role[:name]]>] [--alias <alias=agentId>] [--json] | update --team <id> [--name <displayName>] [--member <agentId[:role[:name]]>] [--alias <alias=agentId>] [--json] | delete --team <id> [--json]"
        )
    }
    let spec = match (cliBuildAgentsTeamRpcSpec(args)) {
        case Some(v) => v
        case None =>
            printUnknownLocalSubcommand("agents team", action, "list|get|create|update|delete [--team <id>] [--name <displayName>] [--template pm-writer-reviewer] [--member <agentId[:role[:name]]>] [--alias <alias=agentId>] [--json]")
            return CLI_EXIT_USAGE_ERROR
    }
    if ((spec.action == "get" || spec.action == "create" || spec.action == "update" || spec.action == "delete") && gatewayAgentsJsonString(spec.params, "id", "").isEmpty()) {
        return cliReturnMissingArgument("agents", "team ${spec.action}", "--team <id>")
    }
    if (spec.action == "update" && !cliAgentsTeamHasAnyUpdateField(spec.params)) {
        return cliReturnMissingArgument("agents", "team update", "--name/--member/--alias")
    }
    let res = gatewayCliClient().call(spec.method, params: spec.params)
    if (!res.ok) {
        return printGatewayRpcFailure("agents", "metis agents team ${spec.action}", res.error)
    }
    if (spec.json) {
        return printJsonObject(res.toJson())
    }
    let result = try {
        res.result.asObject()
    } catch (_e: Exception) {
        JsonObject()
    }
    printGatewayAgentTeamResult(spec.action, result)
}

private func printGatewayAgentMigrationDryRun(result: JsonObject): Int64 {
    let findings = gatewayAgentsJsonArray(result, "findings")
    let bindingApply = match (result.get("bindingApply")) {
        case Some(v) =>
            try { v.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
    PrintUtils.printLine("AgentTeam migration dry-run")
    PrintUtils.printLine("  mode: ${gatewayAgentsJsonString(result, "mode", "")}")
    PrintUtils.printLine("  readOnly: true")
    PrintUtils.printLine("  findings: ${findings.size()}")
    PrintUtils.printLine("  binding added: ${gatewayAgentsJsonArray(bindingApply, "added").size()}")
    PrintUtils.printLine("  binding updated: ${gatewayAgentsJsonArray(bindingApply, "updated").size()}")
    PrintUtils.printLine("  binding skipped: ${gatewayAgentsJsonArray(bindingApply, "skipped").size()}")
    PrintUtils.printLine("  binding conflicts: ${gatewayAgentsJsonArray(bindingApply, "conflicts").size()}")
    CLI_EXIT_OK
}

private func cliRunAgentsMigrateFlow(args: Array<String>): Int64 {
    if (args.size == 1 || args[1].trimAscii().toAsciiLower() == "help") {
        return printLocalFlowUsage(
            "agents migrate",
            "Preview AgentTeam migration diagnostics and route binding changes without writing config",
            [
                "metis agents migrate --dry-run",
                "metis agents migrate --dry-run --config ./legacy-metis.json --json",
                "metis agents migrate --dry-run --binding-json '{\"type\":\"route\",\"agentId\":\"main\",\"match\":{\"channel\":\"telegram\",\"accountId\":\"bot-a\"}}'"
            ],
            "--dry-run [--config <path> | --config-json <json>] [--binding-json <json> ...] [--json]"
        )
    }
    let spec = match (cliBuildAgentsMigrationRpcSpec(args)) {
        case Some(v) => v
        case None =>
            printUnknownLocalSubcommand("agents migrate", firstArg(args[1..]), "--dry-run [--config <path> | --config-json <json>] [--binding-json <json> ...] [--json]")
            return CLI_EXIT_USAGE_ERROR
    }
    let res = gatewayCliClient().call(spec.method, params: spec.params)
    if (!res.ok) {
        return printGatewayRpcFailure("agents", "metis agents migrate", res.error)
    }
    if (spec.json) {
        return printJsonObject(res.toJson())
    }
    let result = try {
        res.result.asObject()
    } catch (_e: Exception) {
        JsonObject()
    }
    printGatewayAgentMigrationDryRun(result)
}

private func printAgentCatalogRows(title: String, rows: JsonArray): Unit {
    if (rows.size() == 0) {
        return
    }
    PrintUtils.printLine(title + ":")
    for (i in 0..rows.size()) {
        let row = try {
            rows[i].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let id = match (row.get("id")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_inner: Exception) { "" }
            case None => ""
        }
        if (id.isEmpty()) {
            continue
        }
        let health = match (row.get("health")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_inner: Exception) { "" }
            case None => ""
        }
        let path = match (row.get("path")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_inner: Exception) { "" }
            case None => ""
        }
        var line = "  - ${id}"
        if (!health.isEmpty()) {
            line += " [${health}]"
        }
        if (!path.isEmpty()) {
            line += " ${path}"
        }
        PrintUtils.printLine(line)
    }
}

private func printAgentCapabilitiesRows(rows: JsonArray): Unit {
    for (i in 0..rows.size()) {
        let row = try {
            rows[i].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let id = match (row.get("id")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_inner: Exception) { "" }
            case None => ""
        }
        if (id.isEmpty()) {
            continue
        }
        let capabilityValues = ArrayList<String>()
        match (row.get("capabilities")) {
            case Some(v) =>
                try {
                    let arr = v.asArray()
                    for (j in 0..arr.size()) {
                        try {
                            capabilityValues.add(arr[j].asString().getValue())
                        } catch (_inner: Exception) {
                            ()
                        }
                    }
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
        let capabilityLine = String.join(capabilityValues.toArray(), delimiter: ", ")
        PrintUtils.printLine("  - ${id}: ${capabilityLine}")
    }
}

private func gatewayAgentsCollectRepeatedStringFlag(args: Array<String>, flag: String): Array<String> {
    let out = ArrayList<String>()
    var i: Int64 = 1
    while (i < args.size) {
        if (args[i].trimAscii().toAsciiLower() == flag) {
            if (i + 1 < args.size) {
                let value = args[i + 1].trimAscii()
                if (!value.isEmpty()) {
                    out.add(value)
                }
            }
            i += 2
            continue
        }
        i += 1
    }
    out.toArray()
}

private func buildCommandEnvelope(command: String, subcommand: String): JsonObject {
    let obj = JsonObject()
    obj.put("status", JsonString("ok"))
    obj.put("command", JsonString(command))
    obj.put("subcommand", JsonString(subcommand))
    obj.put("kind", JsonString(command))
    obj
}

private func printLocalFlowUsage(title: String, subtitle: String, usage: Array<String>, subcommands: String): Int64 {
    PrintUtils.printLine("Metis ${title}")
    PrintUtils.printLine(subtitle)
    PrintUtils.printLine("Usage:")
    for (line in usage) {
        PrintUtils.printLine("  ${line}")
    }
    PrintUtils.printLine("")
    PrintUtils.printLine("Supported subcommands: ${subcommands}")
    PrintUtils.printLine("Hint: run metis ${title} help for command details.")
    PrintUtils.printLine("Machine output: add --json to read-only commands that support structured output.")
    CLI_EXIT_OK
}

private func printUnknownLocalSubcommand(command: String, sub: String, supported: String): Int64 {
    cliReturnUnknownSubcommand(command, sub, supported)
}

private func resolveCliLocalModel(): String {
    try {
        CliConfig.model
    } catch (_ : Exception) {
        "ark:kimi-k2-250905"
    }
}

private func cliBuildLocalModelSelectionView(): JsonObject {
    try {
        return cliBuildModelSelectionView()
    } catch (_ : Exception) {
        let obj = JsonObject()
        obj.put("current", JsonString(cliCurrentModelRef()))
        obj.put("runtimeCurrent", JsonString(""))
        obj.put("fastModel", JsonString(cliFastModelRef()))
        obj.put("fallbackModels", cliFallbackModelJson())
        let candidates = ArrayList<JsonValue>()
        candidates.add(JsonString(cliCurrentModelRef()))
        obj.put("candidateModels", JsonArray(candidates))
        obj.put("diagnostic", JsonString("runtime model selection is not configured; using local default summary"))
        return obj
    }
}

private func buildPathSummary(kind: String): JsonObject {
    let obj = JsonObject()
    obj.put("kind", JsonString(kind))
    obj.put("home", JsonString(CliConfig.dotDir.toString()))
    obj.put("configPath", JsonString(MetisPaths.configPath().toString()))
    obj.put("workspace", JsonString(CliConfig.cwd.toString()))
    obj.put("logsDir", JsonString(CliConfig.logsDir.toString()))
    obj
}

private func putNextSteps(obj: JsonObject, steps: Array<String>): Unit {
    let arr = ArrayList<JsonValue>()
    for (step in steps) {
        arr.add(JsonString(step))
    }
    obj.put("nextSteps", JsonArray(arr))
}

private func parseModelListArgs(args: Array<String>, start: Int64): Array<String> {
    let out = ArrayList<String>()
    for (idx in start..args.size) {
        let chunk = args[idx].trimAscii()
        if (chunk.isEmpty()) {
            continue
        }
        for (item in chunk.split(",")) {
            let trimmed = item.trimAscii()
            if (!trimmed.isEmpty()) {
                out.add(trimmed)
            }
        }
    }
    out.toArray()
}

private func cliWarnSecretCliFlag(flag: String): Unit {
    PrintUtils.printLine("Warning: ${flag} can be exposed via process listings. Prefer ${flag}-file.")
}

private func cliMcpShowNameArg(args: Array<String>): String {
    var i: Int64 = 1
    while (i < args.size) {
        let t = args[i].trimAscii()
        let low = t.toAsciiLower()
        if (low != "--json" && low != "json") {
            return t
        }
        i += 1
    }
    ""
}

private func cliMcpJsonString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func cliMcpArrayCount(obj: JsonObject, key: String): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            try { Int64(v.asArray().size()) } catch (_e: Exception) { 0 }
        case None => 0
    }
}

private func cliMcpServerSummary(value: JsonValue): String {
    let obj = try {
        value.asObject()
    } catch (_e: Exception) {
        return "structured value (use --json for machine output)"
    }
    let command = cliMcpJsonString(obj, "command")
    let url = cliMcpJsonString(obj, "url")
    let transport = cliMcpJsonString(obj, "transport")
    let argsCount = cliMcpArrayCount(obj, "args")
    let envCount = match (obj.get("env")) {
        case Some(v) =>
            try { Int64(v.asObject().getFields().size) } catch (_e: Exception) { 0 }
        case None => 0
    }
    let parts = ArrayList<String>()
    if (!transport.isEmpty()) { parts.add("transport=${transport}") }
    if (!command.isEmpty()) { parts.add("command=${command}") }
    if (!url.isEmpty()) { parts.add("url=${url}") }
    if (argsCount > 0) { parts.add("args=${argsCount}") }
    if (envCount > 0) { parts.add("env=${envCount}") }
    if (parts.size == 0) {
        return "configured (use --json for machine output)"
    }
    String.join(parts.toArray(), delimiter: "  ")
}

func cliMcpRenderServersForHuman(obj: JsonObject): String {
    let fields = obj.getFields()
    let lines = ArrayList<String>()
    lines.add("MCP servers (${mcpConfiguredServersPath()}):")
    if (fields.isEmpty()) {
        lines.add("  (none)")
        lines.add("Next: metis mcp set <name> '<json>'")
        return String.join(lines.toArray(), delimiter: "\n")
    }
    let names = ArrayList<String>()
    for ((name, _) in fields) {
        names.add(name)
    }
    sort(names)
    for (name in names) {
        match (obj.get(name)) {
            case Some(value) => lines.add("  - ${name}: ${cliMcpServerSummary(value)}")
            case None => ()
        }
    }
    lines.add("Machine output: rerun with --json.")
    String.join(lines.toArray(), delimiter: "\n")
}

func cliMcpRenderServerForHuman(name: String, value: JsonValue): String {
    let lines = ArrayList<String>()
    lines.add("MCP server: ${name}")
    lines.add("  ${cliMcpServerSummary(value)}")
    lines.add("Config path: ${mcpConfiguredServersPath()}")
    lines.add("Machine output: rerun with --json.")
    String.join(lines.toArray(), delimiter: "\n")
}

public func cliRunMcpFlow(args: Array<String>): Int64 {
    let sub = firstArg(args)
    if (sub.isEmpty() || sub == "help") {
        return printLocalFlowUsage(
            "mcp",
            "Manage MCP servers and expose the unified Gateway main runtime over MCP stdio",
            [
                "metis mcp serve --url ws://127.0.0.1:18788/ws",
                "metis mcp list",
                "metis mcp show <name>",
                "metis mcp set <name> '{\"command\":\"uvx\",\"args\":[\"context7-mcp\"]}'",
                "metis mcp unset <name>"
            ],
            "serve [--url <url>] [--token <token>|--token-file <path>] [--password <password>|--password-file <path>] [--claude-channel-mode <auto|on|off>] [--verbose] | list | show [name] | set <name> <json> | unset <name> | help"
        )
    }
    if (sub == "list") {
        let obj = mcpConfiguredServersJson()
        let fields = obj.getFields()
        if (fields.isEmpty()) {
            PrintUtils.printLine("No MCP servers configured in ${mcpConfiguredServersPath()}.")
            return CLI_EXIT_OK
        }
        let names = ArrayList<String>()
        for ((name, _) in fields) {
            names.add(name)
        }
        sort(names)
        PrintUtils.printLine("MCP servers (${mcpConfiguredServersPath()}):")
        for (name in names) {
            PrintUtils.printLine("- ${name}")
        }
        return CLI_EXIT_OK
    }
    if (sub == "show") {
        let name = cliMcpShowNameArg(args)
        if (name.isEmpty()) {
            if (localArgsWantJson(args)) {
                return printJsonObject(mcpConfiguredServersJson())
            }
            for (line in cliMcpRenderServersForHuman(mcpConfiguredServersJson()).split("\n")) {
                PrintUtils.printLine(line)
            }
            return CLI_EXIT_OK
        }
        match (mcpConfiguredServerJson(name)) {
            case Some(value) =>
                if (localArgsWantJson(args)) {
                    return printJsonValue(value)
                }
                for (line in cliMcpRenderServerForHuman(name, value).split("\n")) {
                    PrintUtils.printLine(line)
                }
                return CLI_EXIT_OK
            case None =>
                PrintUtils.printLine("No MCP server named \"${name}\" in ${mcpConfiguredServersPath()}.")
                return CLI_EXIT_USAGE_ERROR
        }
    }
    if (sub == "set") {
        let name = argAt(args, 1)
        if (name.isEmpty()) {
            return cliReturnMissingArgument("mcp", "set", "<name>")
        }
        let rawValue = joinArgs(args, start: 2)
        if (rawValue.isEmpty()) {
            return cliReturnMissingArgument("mcp", "set", "<json>")
        }
        let value = try {
            JsonValue.fromStr(rawValue)
        } catch (e: Exception) {
            PrintUtils.printLine("Invalid MCP server JSON: ${e.message}")
            return CLI_EXIT_USAGE_ERROR
        }
        let (ok, err) = mcpSetConfiguredServerJson(name, value)
        if (!ok) {
            PrintUtils.printLine(err)
            return CLI_EXIT_USAGE_ERROR
        }
        PrintUtils.printLine("Saved MCP server \"${name}\" to ${mcpConfiguredServersPath()}.")
        return CLI_EXIT_OK
    }
    if (sub == "unset") {
        let name = argAt(args, 1)
        if (name.isEmpty()) {
            return cliReturnMissingArgument("mcp", "unset", "<name>")
        }
        let (ok, removed, err) = mcpUnsetConfiguredServerJson(name)
        if (!ok) {
            PrintUtils.printLine(err)
            return CLI_EXIT_USAGE_ERROR
        }
        if (!removed) {
            PrintUtils.printLine("No MCP server named \"${name}\" in ${mcpConfiguredServersPath()}.")
            return CLI_EXIT_USAGE_ERROR
        }
        PrintUtils.printLine("Removed MCP server \"${name}\" from ${mcpConfiguredServersPath()}.")
        return CLI_EXIT_OK
    }
    if (sub == "serve") {
        var url = ""
        var token = ""
        var tokenFile = ""
        var password = ""
        var passwordFile = ""
        var claudeChannelMode = "auto"
        var verbose = false
        var i: Int64 = 1
        while (i < args.size) {
            let tokenArg = args[i].trimAscii()
            let low = tokenArg.toAsciiLower()
            if (low == "--url") {
                if (i + 1 >= args.size) {
                    return cliReturnMissingArgument("mcp", low, "<url>")
                }
                url = args[i + 1].trimAscii()
                i += 2
                continue
            }
            if (low == "--token") {
                if (i + 1 >= args.size) {
                    return cliReturnMissingArgument("mcp", low, "<token>")
                }
                token = args[i + 1].trimAscii()
                cliWarnSecretCliFlag("--token")
                i += 2
                continue
            }
            if (low == "--token-file") {
                if (i + 1 >= args.size) {
                    return cliReturnMissingArgument("mcp", low, "<path>")
                }
                tokenFile = args[i + 1].trimAscii()
                i += 2
                continue
            }
            if (low == "--password") {
                if (i + 1 >= args.size) {
                    return cliReturnMissingArgument("mcp", low, "<password>")
                }
                password = args[i + 1].trimAscii()
                cliWarnSecretCliFlag("--password")
                i += 2
                continue
            }
            if (low == "--password-file") {
                if (i + 1 >= args.size) {
                    return cliReturnMissingArgument("mcp", low, "<path>")
                }
                passwordFile = args[i + 1].trimAscii()
                i += 2
                continue
            }
            if (low == "--claude-channel-mode") {
                if (i + 1 >= args.size) {
                    return cliReturnMissingArgument("mcp", low, "<mode>")
                }
                claudeChannelMode = args[i + 1].trimAscii().toAsciiLower()
                i += 2
                continue
            }
            if (low == "--verbose" || low == "-v") {
                verbose = true
                i += 1
                continue
            }
            return cliReturnInvalidArgument("mcp", "serve", tokenArg, "--url <url> | --token <token> | --token-file <path> | --password <password> | --password-file <path> | --claude-channel-mode <auto|on|off> | --verbose")
        }
        if (claudeChannelMode != "auto" && claudeChannelMode != "on" && claudeChannelMode != "off") {
            return cliReturnInvalidArgument("mcp", "serve", claudeChannelMode, "auto | on | off")
        }
        let resolvedToken = try {
            mcpResolveSecretOption(
                direct: token,
                file: tokenFile,
                directFlag: "--token",
                fileFlag: "--token-file",
                label: "Gateway token"
            )
        } catch (e: Exception) {
            PrintUtils.printLine(e.message)
            return CLI_EXIT_USAGE_ERROR
        }
        let resolvedPassword = try {
            mcpResolveSecretOption(
                direct: password,
                file: passwordFile,
                directFlag: "--password",
                fileFlag: "--password-file",
                label: "Gateway password"
            )
        } catch (e: Exception) {
            PrintUtils.printLine(e.message)
            return CLI_EXIT_USAGE_ERROR
        }
        return serveMetisChannelMcp(
            options: MetisMcpServeOptions(
                gatewayUrl: url,
                gatewayToken: resolvedToken,
                gatewayPassword: resolvedPassword,
                claudeChannelMode: claudeChannelMode,
                verbose: verbose
            )
        )
    }
    printUnknownLocalSubcommand("mcp", sub, "serve | list | show [name] | set <name> <json> | unset <name> | help")
}

public func cliRunConfigFlow(args: Array<String>): Int64 {
    let sub = firstArg(args)
    if (sub.isEmpty() || sub == "help") {
        return printLocalFlowUsage(
            "config",
            "Inspect and manage local configuration",
            ["metis config", "metis config path", "metis config show", "metis config workspace",
                "metis config defaults", "metis config validate", "metis config get <key>",
                "metis config set <field> <value...>"],
            "path | show | workspace | defaults | validate | get <key> | set <field> <value...> | help"
        )
    }
    if (sub == "path") {
        PrintUtils.printLine(MetisPaths.configPath().toString())
        return CLI_EXIT_OK
    }
    if (sub == "show") {
        let path = MetisPaths.configPath()
        if (localArgsWantJson(args)) {
            if (exists(path)) {
                PrintUtils.printLine(readFile(path))
            } else {
                PrintUtils.printLine("{}")
            }
            return CLI_EXIT_OK
        }
        let obj = buildCommandEnvelope("config", "show")
        obj.put("exists", JsonBool(exists(path)))
        obj.put("configPath", JsonString(path.toString()))
        obj.put("workspace", JsonString(CliConfig.cwd.toString()))
        putNextSteps(obj, ["metis config show --json", "metis config validate"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "workspace") {
        PrintUtils.printLine(CliConfig.cwd.toString())
        return CLI_EXIT_OK
    }
    if (sub == "defaults") {
        let obj = JsonObject()
        obj.put("kind", JsonString("config"))
        obj.put("workspace", JsonString(CliConfig.cwd.toString()))
        obj.put("configPath", JsonString(MetisPaths.configPath().toString()))
        obj.put("modelConfig", cliBuildCurrentModelConfigView())
        obj.put("modelRuntime", cliBuildModelRuntimeStateView())
        obj.put("modelSelection", cliBuildLocalModelSelectionView())
        putNextSteps(obj, ["metis configure", "metis config show"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "validate") {
        let obj = JsonObject()
        obj.put("kind", JsonString("config"))
        obj.put("exists", JsonBool(exists(MetisPaths.configPath())))
        obj.put("configPath", JsonString(MetisPaths.configPath().toString()))
        obj.put("workspace", JsonString(CliConfig.cwd.toString()))
        obj.put("gatewayEnabled", JsonBool(CliSettingManager.readGatewaySettings().enabled))
        obj.put("modelConfig", cliBuildCurrentModelConfigView())
        obj.put("modelRuntime", cliBuildModelRuntimeStateView())
        obj.put("modelSelection", cliBuildLocalModelSelectionView())
        putNextSteps(obj, ["metis config show", "metis configure"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "get") {
        let key = argAt(args, 1).toAsciiLower()
        if (key.isEmpty()) {
            return cliReturnMissingArgument("config", "get", "<key>")
        }
        let obj = JsonObject()
        obj.put("kind", JsonString("config"))
        obj.put("key", JsonString(key))
        if (key == "model") {
            obj.put("value", JsonString(resolveCliLocalModel()))
            putNextSteps(obj, ["metis models current", "metis config defaults"])
            return localPrintCommandResult(args, obj)
        }
        if (key == "provider") {
            obj.put("value", JsonString(cliCurrentProviderId()))
            putNextSteps(obj, ["metis models providers", "metis models status"])
            return localPrintCommandResult(args, obj)
        }
        if (key == "api-key-config-path") {
            obj.put("value", JsonString(cliCurrentApiKeyConfigPath()))
            putNextSteps(obj, ["metis models status", "metis configure"])
            return localPrintCommandResult(args, obj)
        }
        if (key == "base-url-config-path") {
            obj.put("value", JsonString(cliCurrentBaseUrlConfigPath()))
            putNextSteps(obj, ["metis models status", "metis configure"])
            return localPrintCommandResult(args, obj)
        }
        if (key == "base-url") {
            obj.put("value", JsonString(cliCurrentBaseUrl()))
            putNextSteps(obj, ["metis models status", "metis configure"])
            return localPrintCommandResult(args, obj)
        }
        if (key == "fast-model") {
            obj.put("value", JsonString(cliFastModelRef()))
            putNextSteps(obj, ["metis models status", "metis config defaults"])
            return localPrintCommandResult(args, obj)
        }
        if (key == "fallback-models") {
            obj.put("value", cliFallbackModelJson())
            putNextSteps(obj, ["metis models status", "metis config defaults"])
            return localPrintCommandResult(args, obj)
        }
        if (key == "input-limit") {
            obj.put("value", CliConfig.defaultModelInputLimit.toJsonValue())
            putNextSteps(obj, ["metis config defaults", "metis models status"])
            return localPrintCommandResult(args, obj)
        }
        if (key == "output-limit") {
            obj.put("value", CliConfig.defaultModelOutputLimit.toJsonValue())
            putNextSteps(obj, ["metis config defaults", "metis models status"])
            return localPrintCommandResult(args, obj)
        }
        if (key == "workspace") {
            obj.put("value", JsonString(CliConfig.cwd.toString()))
            putNextSteps(obj, ["metis system paths", "metis config path"])
            return localPrintCommandResult(args, obj)
        }
        if (key == "config-path" || key == "config") {
            obj.put("value", JsonString(MetisPaths.configPath().toString()))
            putNextSteps(obj, ["metis config show", "metis config validate"])
            return localPrintCommandResult(args, obj)
        }
        return printUnknownLocalSubcommand("config", "get", "<model|provider|api-key-env|base-url-env|base-url|fast-model|fallback-models|input-limit|output-limit|workspace|config-path> | help")
    }
    if (sub == "set") {
        let field = argAt(args, 1).toAsciiLower()
        if (field.isEmpty()) {
            return cliReturnMissingArgument("config", "set", "<field>")
        }
        let obj = JsonObject()
        obj.put("kind", JsonString("config"))
        obj.put("action", JsonString("set"))
        obj.put("field", JsonString(field))
        if (field == "model") {
            let value = argAt(args, 2)
            if (value.isEmpty()) {
                return cliReturnMissingArgument("config", "set", "<model>")
            }
            let next = MetisConfigManager.setPrimaryModelRef(value)
            obj.put("value", JsonString(next))
            obj.put("modelConfig", cliBuildCurrentModelConfigView())
            obj.put("modelRuntime", cliBuildModelRuntimeStateView())
            obj.put("modelSelection", cliBuildLocalModelSelectionView())
            putNextSteps(obj, ["metis models status", "metis config defaults"])
            return localPrintMutationResult(args, obj, "this updates local model configuration.")
        }
        if (field == "provider") {
            let provider = argAt(args, 2)
            if (provider.isEmpty()) {
                return cliReturnMissingArgument("config", "set", "<provider>")
            }
            match (cliFindModelProviderDescriptor(provider)) {
                case Some(descriptor) =>
                    let next = MetisConfigManager.setPrimaryModelRef(descriptor.defaultModelRef)
                    obj.put("provider", JsonString(descriptor.providerId))
                    obj.put("value", JsonString(next))
                    obj.put("modelConfig", cliBuildCurrentModelConfigView())
                    obj.put("modelRuntime", cliBuildModelRuntimeStateView())
                    obj.put("modelSelection", cliBuildLocalModelSelectionView())
                    putNextSteps(obj, ["metis models providers", "metis models status"])
                    return localPrintMutationResult(args, obj, "this updates local model configuration.")
                case None =>
                    return cliReturnInvalidArgument("config", "set", provider, "known provider id")
            }
        }
        if (field == "fallback-models") {
            let values = parseModelListArgs(args, 2)
            let next = if (values.size == 1 && (values[0].toAsciiLower() == "none" || values[0].toAsciiLower() == "clear")) {
                MetisConfigManager.setFallbackModelRefs(Array<String>())
            } else {
                MetisConfigManager.setFallbackModelRefs(values)
            }
            let applied = ArrayList<JsonValue>()
            for (item in next) {
                applied.add(JsonString(item))
            }
            obj.put("value", cliFallbackModelJson())
            obj.put("applied", JsonArray(applied))
            obj.put("modelSelection", cliBuildLocalModelSelectionView())
            putNextSteps(obj, ["metis models status", "metis config defaults"])
            return localPrintMutationResult(args, obj, "this updates local model fallback configuration.")
        }
        if (field == "workspace") {
            let value = joinArgs(args, start: 2)
            if (value.isEmpty()) {
                return cliReturnMissingArgument("config", "set", "<workspace>")
            }
            let next = MetisConfigManager.setWorkspace(value)
            obj.put("value", JsonString(next))
            putNextSteps(obj, ["metis config path", "metis system paths"])
            return localPrintMutationResult(args, obj, "this updates the default workspace in local configuration.")
        }
        if (field == "api-key") {
            let provider = argAt(args, 2)
            let value = argAt(args, 3)
            if (provider.isEmpty() || value.isEmpty()) {
                return cliReturnMissingArgument("config", "set", "<provider> <api-key>")
            }
            let applied = MetisConfigManager.setProviderApiKey(provider, value)
            obj.put("provider", JsonString(MetisConfigManager.canonicalModelProviderId(provider)))
            obj.put("value", JsonString(applied))
            obj.put("modelConfig", cliBuildCurrentModelConfigView())
            putNextSteps(obj, ["metis models providers", "metis models status"])
            return localPrintMutationResult(args, obj, "this stores provider credentials in local configuration.")
        }
        if (field == "base-url") {
            let provider = argAt(args, 2)
            let value = argAt(args, 3)
            if (provider.isEmpty() || value.isEmpty()) {
                return cliReturnMissingArgument("config", "set", "<provider> <base-url>")
            }
            let validation = cliValidateProviderBaseUrl(provider, value)
            if (!validation.trimAscii().isEmpty()) {
                return cliReturnInvalidArgument("config", "set", value, validation)
            }
            let applied = MetisConfigManager.setProviderBaseUrl(provider, value)
            obj.put("provider", JsonString(MetisConfigManager.canonicalModelProviderId(provider)))
            obj.put("value", JsonString(applied))
            obj.put("modelConfig", cliBuildCurrentModelConfigView())
            putNextSteps(obj, ["metis models providers", "metis models status"])
            return localPrintMutationResult(args, obj, "this updates provider endpoint configuration.")
        }
        return printUnknownLocalSubcommand("config", "set", "<model|provider|fallback-models|workspace|api-key|base-url>")
    }
    printUnknownLocalSubcommand("config", sub, "path | show | workspace | defaults | validate | get <key> | set <field> <value...> | help")
}

public func cliRunBackupFlow(args: Array<String>): Int64 {
    let sub = firstArg(args)
    if (sub.isEmpty() || sub == "help") {
        return printLocalFlowUsage(
            "backup",
            "Inspect backup scope and backup state",
            ["metis backup", "metis backup state", "metis backup path", "metis backup preview"],
            "state | path | preview | help"
        )
    }
    if (sub == "path") {
        PrintUtils.printLine(CliConfig.dotDir.toString())
        return CLI_EXIT_OK
    }
    if (sub == "state") {
        let obj = buildPathSummary("backup")
        obj.put("preview", JsonBool(true))
        let scope = ArrayList<JsonValue>()
        scope.add(JsonString("config"))
        scope.add(JsonString("logs"))
        scope.add(JsonString("workspace"))
        obj.put("scope", JsonArray(scope))
        putNextSteps(obj, ["metis backup preview", "metis backup path"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "preview") {
        let obj = JsonObject()
        obj.put("kind", JsonString("backup"))
        obj.put("mode", JsonString("preview"))
        obj.put("path", JsonString(CliConfig.dotDir.toString()))
        putNextSteps(obj, ["metis backup state", "metis config path"])
        return localPrintCommandResult(args, obj)
    }
    printUnknownLocalSubcommand("backup", sub, "state | path | preview | help")
}

public func cliRunResetFlow(args: Array<String>): Int64 {
    let sub = firstArg(args)
    if (sub.isEmpty() || sub == "help") {
        return printLocalFlowUsage(
            "reset",
            "Preview reset scope and reset targets",
            ["metis reset", "metis reset preview", "metis reset state", "metis reset targets"],
            "state | preview | targets | help"
        )
    }
    if (sub == "state" || sub == "preview") {
        let obj = buildPathSummary("reset")
        let targets = ArrayList<JsonValue>()
        targets.add(JsonString("logs"))
        targets.add(JsonString("readline.history"))
        targets.add(JsonString("conversation-history"))
        obj.put("targets", JsonArray(targets))
        putNextSteps(obj, ["metis reset targets", "metis backup state"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "targets") {
        let obj = JsonObject()
        let targets = ArrayList<JsonValue>()
        targets.add(JsonString("logs"))
        targets.add(JsonString("readline.history"))
        targets.add(JsonString("conversation-history"))
        obj.put("kind", JsonString("reset"))
        obj.put("targets", JsonArray(targets))
        putNextSteps(obj, ["metis reset preview", "metis backup state"])
        return localPrintCommandResult(args, obj)
    }
    printUnknownLocalSubcommand("reset", sub, "state | preview | targets | help")
}

public func cliRunUninstallFlow(args: Array<String>): Int64 {
    let sub = firstArg(args)
    if (sub.isEmpty() || sub == "help") {
        return printLocalFlowUsage(
            "uninstall",
            "Preview local uninstall scope",
            ["metis uninstall", "metis uninstall preview", "metis uninstall state", "metis uninstall path"],
            "preview | state | path | help"
        )
    }
    if (sub == "path") {
        PrintUtils.printLine(CliConfig.dotDir.toString())
        return CLI_EXIT_OK
    }
    if (sub == "preview" || sub == "state") {
        let obj = buildPathSummary("uninstall")
        obj.put("rootRemoval", JsonBool(true))
        putNextSteps(obj, ["metis uninstall path", "metis backup preview"])
        return localPrintCommandResult(args, obj)
    }
    printUnknownLocalSubcommand("uninstall", sub, "preview | state | path | help")
}

public func cliRunMessageFlow(args: Array<String>): Int64 {
    let sub = firstArg(args)
    if (sub.isEmpty()) {
        return printLocalFlowUsage(
            "message",
            "Preview and inspect explicit message payloads; use `agent --message` for formal agent turns",
            ["metis message <text...>", "metis message preview <text...>", "metis message json <text...>",
                "metis message file <path>"],
            "preview | json | file <path> | help"
        )
    }
    if (sub == "help") {
        return printLocalFlowUsage(
            "message",
            "Preview and inspect explicit message payloads; use `agent --message` for formal agent turns",
            ["metis message <text...>", "metis message preview <text...>", "metis message json <text...>",
                "metis message file <path>"],
            "preview | json | file <path> | help"
        )
    }
    if (sub == "file") {
        let path = argAt(args, 1)
        if (path.isEmpty()) {
            return cliReturnMissingArgument("message", "file", "<path>")
        }
        let obj = JsonObject()
        obj.put("kind", JsonString("message"))
        obj.put("source", JsonString("file"))
        obj.put("path", JsonString(path))
        obj.put("exists", JsonBool(exists(path)))
        if (exists(path)) {
            obj.put("text", JsonString(readFile(Path(path)).trimAscii()))
        }
        obj.put("dispatchMode", JsonString("local-preview"))
        obj.put("model", JsonString(resolveCliLocalModel()))
        putNextSteps(obj, ["metis agent --message \"$(cat ${path})\"", "metis --prompt-file ${path}"])
        return localPrintCommandResult(args, obj)
    }
    let payload = if (sub == "preview" || sub == "json") { joinArgs(args, start: 1) } else { joinArgs(args) }
    if ((sub == "preview" || sub == "json") && payload.isEmpty()) {
        return cliReturnMissingArgument("message", sub, "<text...>")
    }
    if (!payload.isEmpty()) {
        let obj = JsonObject()
        obj.put("kind", JsonString("message"))
        obj.put("text", JsonString(payload))
        obj.put("dispatchMode", JsonString("local-preview"))
        obj.put("model", JsonString(resolveCliLocalModel()))
        putNextSteps(obj, ["metis agent --message \"${payload}\"", "metis tasks current"])
        return localPrintCommandResult(args, obj)
    }
    printUnknownLocalSubcommand("message", sub, "preview <text...> | json <text...> | file <path> | help")
}

public func cliRunAgentFlow(args: Array<String>): Int64 {
    var message = ""
    var sessionKey = ""
    var to = ""
    var agentId = ""
    var local = false
    var thinking = ""
    var verbose = ""
    var timeoutSeconds: Int64 = 0
    var deliver = false
    var bestEffortDeliver = false
    var json = false
    var lane = ""
    var runId = ""
    var extraSystemPrompt = ""
    var replyTo = ""
    var replyChannel = ""
    var replyAccount = ""
    var i: Int64 = 0
    while (i < args.size) {
        let token = args[i].trimAscii()
        let low = token.toAsciiLower()
        if (low.isEmpty()) {
            i += 1
            continue
        }
        if (low == "help" || low == "-h" || low == "--help") {
            return printLocalFlowUsage(
            "agent",
            "Run the formal single-turn agent entrypoint via the unified Gateway main runtime (--local is the only embedded path)",
            ["metis agent --message \"Summarize this repo\"", "metis agent --prompt \"Summarize this repo\"",
                "metis agent --message \"Summarize this repo\" --session-id main",
                "metis agent --message \"Send to QQ\" --to qq:user:12345 --deliver",
                    "metis agent --message \"Use the code agent\" --agent code --thinking medium --verbose full",
                    "metis agent --message \"Summarize this repo\" --json --timeout 60 --lane review",
                    "metis agent --message \"Reply in QQ\" --deliver --reply-channel qq --reply-to user:12345",
                    "metis agent --message \"Summarize this repo\" --local"],
                "--message <text> | --prompt <text> [--session-id <id>] [--to <target>] [--agent <id>] [--thinking <level>] [--verbose <mode>] [--timeout <seconds>] [--deliver] [--best-effort-deliver] [--lane <name>] [--run-id <id>] [--extra-system-prompt <text>] [--reply-channel <channel>] [--reply-to <target>] [--reply-account <id>] [--json] [--local] | help"
            )
        }
        if (low == "--local") {
            local = true
            i += 1
            continue
        }
        if (low == "--json") {
            json = true
            i += 1
            continue
        }
        if (low == "--message" || low == "--prompt") {
            if (i + 1 >= args.size) {
                return cliReturnMissingArgument("agent", low, "<text>")
            }
            message = args[i + 1]
            i += 2
            continue
        }
        if (low == "--session-id") {
            if (i + 1 >= args.size) {
                return cliReturnMissingArgument("agent", low, "<id>")
            }
            sessionKey = args[i + 1].trimAscii()
            i += 2
            continue
        }
        if (low == "--to") {
            if (i + 1 >= args.size) {
                return cliReturnMissingArgument("agent", low, "<target>")
            }
            to = args[i + 1].trimAscii()
            i += 2
            continue
        }
        if (low == "--agent") {
            if (i + 1 >= args.size) {
                return cliReturnMissingArgument("agent", low, "<id>")
            }
            agentId = args[i + 1].trimAscii()
            i += 2
            continue
        }
        if (low == "--thinking") {
            if (i + 1 >= args.size) {
                return cliReturnMissingArgument("agent", low, "<level>")
            }
            thinking = args[i + 1].trimAscii()
            i += 2
            continue
        }
        if (low == "--verbose") {
            if (i + 1 >= args.size) {
                return cliReturnMissingArgument("agent", low, "<mode>")
            }
            verbose = args[i + 1].trimAscii()
            i += 2
            continue
        }
        if (low == "--timeout") {
            if (i + 1 >= args.size) {
                return cliReturnMissingArgument("agent", low, "<seconds>")
            }
            try {
                timeoutSeconds = Int64.parse(args[i + 1].trimAscii())
            } catch (_e: Exception) {
                return cliReturnInvalidArgument("agent", low, args[i + 1], "<seconds>")
            }
            i += 2
            continue
        }
        if (low == "--deliver") {
            deliver = true
            i += 1
            continue
        }
        if (low == "--best-effort-deliver") {
            bestEffortDeliver = true
            i += 1
            continue
        }
        if (low == "--lane") {
            if (i + 1 >= args.size) {
                return cliReturnMissingArgument("agent", low, "<name>")
            }
            lane = args[i + 1].trimAscii()
            i += 2
            continue
        }
        if (low == "--run-id") {
            if (i + 1 >= args.size) {
                return cliReturnMissingArgument("agent", low, "<id>")
            }
            runId = args[i + 1].trimAscii()
            i += 2
            continue
        }
        if (low == "--extra-system-prompt") {
            if (i + 1 >= args.size) {
                return cliReturnMissingArgument("agent", low, "<text>")
            }
            extraSystemPrompt = args[i + 1]
            i += 2
            continue
        }
        if (low == "--reply-to") {
            if (i + 1 >= args.size) {
                return cliReturnMissingArgument("agent", low, "<target>")
            }
            replyTo = args[i + 1].trimAscii()
            i += 2
            continue
        }
        if (low == "--reply-channel") {
            if (i + 1 >= args.size) {
                return cliReturnMissingArgument("agent", low, "<channel>")
            }
            replyChannel = args[i + 1].trimAscii()
            i += 2
            continue
        }
        if (low == "--reply-account") {
            if (i + 1 >= args.size) {
                return cliReturnMissingArgument("agent", low, "<id>")
            }
            replyAccount = args[i + 1].trimAscii()
            i += 2
            continue
        }
        return cliReturnInvalidArgument("agent", "run", token, "--message <text> | --prompt <text> | --session-id <id> | --to <target> | --agent <id> | --thinking <level> | --verbose <mode> | --timeout <seconds> | --deliver | --best-effort-deliver | --lane <name> | --run-id <id> | --extra-system-prompt <text> | --reply-channel <channel> | --reply-to <target> | --reply-account <id> | --json | --local")
    }
    if (message.trimAscii().isEmpty()) {
        return cliReturnMissingArgument("agent", "run", "--message <text>")
    }
    if (sessionKey.trimAscii().isEmpty() && to.trimAscii().isEmpty()) {
        sessionKey = "main"
    }
    if (local) {
        runEmbeddedPrompt(message)
        return CLI_EXIT_OK
    }
    if (json) {
        let (ok, result, err) = gatewayInvokeCliAgentResult(
            message,
            sessionKey: sessionKey,
            channel: "cli",
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
            replyAccount: replyAccount
        )
        if (!ok) {
            PrintUtils.printLine("Gateway agent failed: ${err}")
            if (gatewayCliShouldPrintRuntimeRequiredHint(err)) {
                PrintUtils.printLine("Start the unified Gateway main runtime with `metis gateway run`, or use `metis agent --local --message \"...\"` for explicit embedded mode.")
            }
            return CLI_EXIT_USAGE_ERROR
        }
        return printJsonObject(result)
    }
    let (ok, answer, err) = gatewayInvokeCliAgent(
        message,
        sessionKey: sessionKey,
        channel: "cli",
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
        replyAccount: replyAccount
    )
    if (!ok) {
        PrintUtils.printLine("Gateway agent failed: ${err}")
        if (gatewayCliShouldPrintRuntimeRequiredHint(err)) {
            PrintUtils.printLine("Start the unified Gateway main runtime with `metis gateway run`, or use `metis agent --local --message \"...\"` for explicit embedded mode.")
        }
        return CLI_EXIT_USAGE_ERROR
    }
    PrintUtils.printLine("")
    PrintUtils.printLine(PrintUtils.renderAssistantResponseBox(answer))
    PrintUtils.printLine("")
    PrintUtils.printLine("")
    CLI_EXIT_OK
}

public func cliRunAgentsFlow(args: Array<String>): Int64 {
    let sub = firstArg(args)
    if (sub.isEmpty() || sub == "help") {
        return printLocalFlowUsage(
            "agents",
            "Inspect managed agents via the unified Gateway main runtime",
            [
                "metis agents list",
                "metis agents summary",
                "metis agents health",
                "metis agents capabilities",
                "metis agents bindings --agent custom-reviewer",
                "metis agents bind --agent custom-reviewer --bind qq:default",
                "metis agents unbind --agent custom-reviewer --bind qq:default",
                "metis agents team create --team content --template pm-writer-reviewer",
                "metis agents team list --json",
                "metis agents migrate --dry-run --json",
                "metis agents add --agent custom-reviewer --name Reviewer",
                "metis agents add --agent demo --name Demo --model qwen/qwen3.6-plus --feishu cli_test:secret_test --qqbot 1020:test_secret --telegram-bot-token test-token",
                "metis agents update --agent custom-reviewer --model qwen/qwen3.6-plus",
                "metis agents set-identity --agent custom-reviewer --name Reviewer --emoji 🔎",
                "metis agents delete --agent custom-reviewer",
                "metis agents list --json"
            ],
            "list [--json] | summary [--json] | health [--json] | capabilities [--json] | bindings [--agent <id>] [--json] | bind --agent <id> --bind <channel[:account]> [--bind ...] [--json] | unbind --agent <id> (--bind <channel[:account]> [--bind ...] | --all) [--json] | team list|get|create|update|delete [--team <id>] [--json] | migrate --dry-run [--json] | add --agent <id> [--name <text>] [--workspace <path>] [--model <ref>] [--bind <channel[:account]> ...] [--feishu <appId:appSecret>] [--feishu-account <id>] [--qqbot <appId:appSecret>] [--qqbot-account <id>] [--telegram-bot-token <token>] [--telegram-account <id>] [--channel-overwrite] [--json] | update --agent <id> [--model <ref>] [--name <text>] [--workspace <path>] [--json] | set-identity --agent <id> [--name <text>] [--emoji <text>] [--theme <text>] [--avatar <path>] [--json] | delete --agent <id> [--json] | help\n${cliAgentsTeamProductSemanticsHelpText()}"
        )
    }
    if (sub == "add") {
        return cliRunAgentsAddFlow(args)
    }
    if (sub == "update") {
        return cliRunAgentsUpdateFlow(args)
    }
    if (sub == "team") {
        return cliRunAgentsTeamFlow(args)
    }
    if (sub == "migrate") {
        return cliRunAgentsMigrateFlow(args)
    }
    var json = false
    var agentId = ""
    var name = ""
    var workspace = ""
    var model = ""
    var emoji = ""
    var theme = ""
    var avatar = ""
    var unbindAll = false
    var i: Int64 = 1
    while (i < args.size) {
        let token = args[i].trimAscii()
        let low = token.toAsciiLower()
        if (low == "--json") {
            json = true
            i += 1
            continue
        }
        if (low == "--all") {
            unbindAll = true
            i += 1
            continue
        }
        if (low == "--agent") {
            if (i + 1 >= args.size) {
                return cliReturnMissingArgument("agents", sub, "<id>")
            }
            agentId = args[i + 1].trimAscii()
            i += 2
            continue
        }
        if (low == "--name") {
            if (i + 1 >= args.size) {
                return cliReturnMissingArgument("agents", sub, "<text>")
            }
            name = args[i + 1]
            i += 2
            continue
        }
        if (low == "--workspace") {
            if (i + 1 >= args.size) {
                return cliReturnMissingArgument("agents", sub, "<path>")
            }
            workspace = args[i + 1].trimAscii()
            i += 2
            continue
        }
        if (low == "--model") {
            if (i + 1 >= args.size) {
                return cliReturnMissingArgument("agents", sub, "<ref>")
            }
            model = args[i + 1].trimAscii()
            i += 2
            continue
        }
        if (low == "--emoji") {
            if (i + 1 >= args.size) {
                return cliReturnMissingArgument("agents", sub, "<text>")
            }
            emoji = args[i + 1]
            i += 2
            continue
        }
        if (low == "--theme") {
            if (i + 1 >= args.size) {
                return cliReturnMissingArgument("agents", sub, "<text>")
            }
            theme = args[i + 1]
            i += 2
            continue
        }
        if (low == "--avatar") {
            if (i + 1 >= args.size) {
                return cliReturnMissingArgument("agents", sub, "<path>")
            }
            avatar = args[i + 1].trimAscii()
            i += 2
            continue
        }
        if (low == "--bind") {
            if (i + 1 >= args.size) {
                return cliReturnMissingArgument("agents", sub, "<channel[:account]>")
            }
            i += 2
            continue
        }
        return cliReturnInvalidArgument("agents", sub, token, "--json | --agent <id> | --bind <channel[:account]> | --all | --name <text> | --workspace <path> | --model <ref> | --emoji <text> | --theme <text> | --avatar <path>")
    }
    if (sub == "list") {
        let res = gatewayCliClient().call("agents.list")
        if (!res.ok) {
            return printGatewayRpcFailure("agents", "metis agents list", res.error)
        }
        if (json) {
            return printJsonObject(res.toJson())
        }
        let result = try {
            res.result.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let count = gatewayAgentsResultCount(result)
        PrintUtils.printLine("Managed agents: ${count}")
        printAgentCatalogRows("Builtin", gatewayAgentsBuiltinRows(result))
        printAgentCatalogRows("Custom", gatewayAgentsCustomRows(result))
        return CLI_EXIT_OK
    }
    if (sub == "summary") {
        let res = gatewayCliClient().call("agents.summary")
        if (!res.ok) {
            return printGatewayRpcFailure("agents", "metis agents summary", res.error)
        }
        if (json) {
            return printJsonObject(res.toJson())
        }
        let result = try {
            res.result.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let summary = match (result.get("agents")) {
            case Some(v) =>
                try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let builtinCount = gatewayAgentsJsonInt(summary, "builtinCount", 0)
        let customCount = gatewayAgentsJsonInt(summary, "customCount", 0)
        let totalCount = gatewayAgentsJsonInt(summary, "totalCount", 0)
        let healthy = match (summary.get("healthy")) {
            case Some(v) =>
                try { v.asBool().getValue() } catch (_e: Exception) { false }
            case None => false
        }
        let healthyText = if (healthy) { "yes" } else { "no" }
        PrintUtils.printLine("Agents summary")
        PrintUtils.printLine("  builtin: ${builtinCount}")
        PrintUtils.printLine("  custom: ${customCount}")
        PrintUtils.printLine("  total: ${totalCount}")
        PrintUtils.printLine("  healthy: ${healthyText}")
        return CLI_EXIT_OK
    }
    if (sub == "health") {
        let res = gatewayCliClient().call("agents.health")
        if (!res.ok) {
            return printGatewayRpcFailure("agents", "metis agents health", res.error)
        }
        if (json) {
            return printJsonObject(res.toJson())
        }
        let result = try {
            res.result.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let health = match (result.get("agents")) {
            case Some(v) =>
                try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let builtinCount = gatewayAgentsJsonInt(health, "builtinCount", 0)
        let customCount = gatewayAgentsJsonInt(health, "customCount", 0)
        let healthy = match (health.get("healthy")) {
            case Some(v) =>
                try { v.asBool().getValue() } catch (_e: Exception) { false }
            case None => false
        }
        let healthyText = if (healthy) { "yes" } else { "no" }
        PrintUtils.printLine("Agents health")
        PrintUtils.printLine("  builtinCount: ${builtinCount}")
        PrintUtils.printLine("  customCount: ${customCount}")
        PrintUtils.printLine("  healthy: ${healthyText}")
        return CLI_EXIT_OK
    }
    if (sub == "capabilities") {
        let res = gatewayCliClient().call("agents.capabilities")
        if (!res.ok) {
            return printGatewayRpcFailure("agents", "metis agents capabilities", res.error)
        }
        if (json) {
            return printJsonObject(res.toJson())
        }
        let result = try {
            res.result.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let rows = match (result.get("agents")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        PrintUtils.printLine("Agent capabilities")
        printAgentCapabilitiesRows(rows)
        return CLI_EXIT_OK
    }
    if (sub == "bindings") {
        let params = JsonObject()
        if (!agentId.isEmpty()) {
            params.put("agentId", JsonString(agentId))
        }
        let res = gatewayCliClient().call("agents.bindings", params: params)
        if (!res.ok) {
            return printGatewayRpcFailure("agents", "metis agents bindings", res.error)
        }
        if (json) {
            return printJsonObject(res.toJson())
        }
        let result = try {
            res.result.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let rows = match (result.get("bindings")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        if (rows.size() == 0) {
            PrintUtils.printLine(if (agentId.isEmpty()) { "No routing bindings." } else { "No routing bindings for ${agentId}." })
            return CLI_EXIT_OK
        }
        PrintUtils.printLine("Routing bindings:")
        for (idx in 0..rows.size()) {
            let row = try {
                rows[idx].asObject()
            } catch (_e: Exception) {
                JsonObject()
            }
            PrintUtils.printLine("  - ${gatewayAgentsJsonString(row, "agentId", "")} <- ${gatewayAgentsJsonString(row, "description", "")}")
        }
        return CLI_EXIT_OK
    }
    if (sub == "bind") {
        if (agentId.isEmpty()) {
            return cliReturnMissingArgument("agents", "bind", "--agent <id>")
        }
        let binds = gatewayAgentsCollectRepeatedStringFlag(args, "--bind")
        if (binds.isEmpty()) {
            return cliReturnMissingArgument("agents", "bind", "--bind <channel[:account]>")
        }
        let params = JsonObject()
        params.put("agentId", JsonString(agentId))
        let arr = ArrayList<JsonValue>()
        for (item in binds) {
            arr.add(JsonString(item))
        }
        params.put("bind", JsonArray(arr))
        let res = gatewayCliClient().call("agents.bind", params: params)
        if (!res.ok) {
            return printGatewayRpcFailure("agents", "metis agents bind", res.error)
        }
        if (json) {
            return printJsonObject(res.toJson())
        }
        let result = try {
            res.result.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let added = match (result.get("added")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        let skipped = match (result.get("skipped")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        let conflicts = match (result.get("conflicts")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        if (added.size() > 0) {
            PrintUtils.printLine("Added bindings:")
            for (idx in 0..added.size()) {
                try {
                    PrintUtils.printLine("  - ${added[idx].asString().getValue()}")
                } catch (_e: Exception) {
                    ()
                }
            }
        }
        if (skipped.size() > 0) {
            PrintUtils.printLine("Skipped bindings:")
            for (idx in 0..skipped.size()) {
                try {
                    PrintUtils.printLine("  - ${skipped[idx].asString().getValue()}")
                } catch (_e: Exception) {
                    ()
                }
            }
        }
        if (conflicts.size() > 0) {
            PrintUtils.printLine("Conflicts:")
            for (idx in 0..conflicts.size()) {
                let row = try {
                    conflicts[idx].asObject()
                } catch (_e: Exception) {
                    JsonObject()
                }
                PrintUtils.printLine("  - ${gatewayAgentsJsonString(row, "binding", "")} (agent=${gatewayAgentsJsonString(row, "existingAgentId", "")})")
            }
        }
        return CLI_EXIT_OK
    }
    if (sub == "unbind") {
        if (agentId.isEmpty()) {
            return cliReturnMissingArgument("agents", "unbind", "--agent <id>")
        }
        let binds = gatewayAgentsCollectRepeatedStringFlag(args, "--bind")
        if (!unbindAll && binds.isEmpty()) {
            return cliReturnMissingArgument("agents", "unbind", "--bind <channel[:account]> or --all")
        }
        let params = JsonObject()
        params.put("agentId", JsonString(agentId))
        params.put("all", JsonBool(unbindAll))
        let arr = ArrayList<JsonValue>()
        for (item in binds) {
            arr.add(JsonString(item))
        }
        params.put("bind", JsonArray(arr))
        let res = gatewayCliClient().call("agents.unbind", params: params)
        if (!res.ok) {
            return printGatewayRpcFailure("agents", "metis agents unbind", res.error)
        }
        if (json) {
            return printJsonObject(res.toJson())
        }
        let result = try {
            res.result.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let removed = match (result.get("removed")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        let missing = match (result.get("missing")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        if (removed.size() > 0) {
            PrintUtils.printLine("Removed bindings:")
            for (idx in 0..removed.size()) {
                try {
                    PrintUtils.printLine("  - ${removed[idx].asString().getValue()}")
                } catch (_e: Exception) {
                    ()
                }
            }
        }
        if (missing.size() > 0) {
            PrintUtils.printLine("Missing bindings:")
            for (idx in 0..missing.size()) {
                try {
                    PrintUtils.printLine("  - ${missing[idx].asString().getValue()}")
                } catch (_e: Exception) {
                    ()
                }
            }
        }
        return CLI_EXIT_OK
    }
    if (sub == "set-identity") {
        if (agentId.isEmpty()) {
            return cliReturnMissingArgument("agents", "set-identity", "--agent <id>")
        }
        if (name.trimAscii().isEmpty() && emoji.trimAscii().isEmpty() && theme.trimAscii().isEmpty() && avatar.trimAscii().isEmpty()) {
            return cliReturnMissingArgument("agents", "set-identity", "--name/--emoji/--theme/--avatar")
        }
        let params = JsonObject()
        params.put("agentId", JsonString(agentId))
        if (!name.trimAscii().isEmpty()) { params.put("name", JsonString(name.trimAscii())) }
        if (!emoji.trimAscii().isEmpty()) { params.put("emoji", JsonString(emoji.trimAscii())) }
        if (!theme.trimAscii().isEmpty()) { params.put("theme", JsonString(theme.trimAscii())) }
        if (!avatar.trimAscii().isEmpty()) { params.put("avatar", JsonString(avatar.trimAscii())) }
        let res = gatewayCliClient().call("agents.set-identity", params: params)
        if (!res.ok) {
            return printGatewayRpcFailure("agents", "metis agents set-identity", res.error)
        }
        if (json) {
            return printJsonObject(res.toJson())
        }
        let result = try {
            res.result.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        PrintUtils.printLine("Updated identity for ${gatewayAgentsJsonString(result, "agentId", agentId)}")
        return CLI_EXIT_OK
    }
    if (sub == "delete") {
        if (agentId.isEmpty()) {
            return cliReturnMissingArgument("agents", "delete", "--agent <id>")
        }
        let params = JsonObject()
        params.put("agentId", JsonString(agentId))
        let res = gatewayCliClient().call("agents.delete", params: params)
        if (!res.ok) {
            return printGatewayRpcFailure("agents", "metis agents delete", res.error)
        }
        if (json) {
            return printJsonObject(res.toJson())
        }
        let result = try {
            res.result.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        PrintUtils.printLine("Deleted agent: ${gatewayAgentsJsonString(result, "agentId", agentId)}")
        return CLI_EXIT_OK
    }
    printUnknownLocalSubcommand("agents", sub, "list [--json] | summary [--json] | health [--json] | capabilities [--json] | bindings [--agent <id>] [--json] | bind --agent <id> --bind <channel[:account]> [--bind ...] [--json] | unbind --agent <id> (--bind <channel[:account]> [--bind ...] | --all) [--json] | team list|get|create|update|delete [--team <id>] [--json] | migrate --dry-run [--json] | add --agent <id> [--name <text>] [--workspace <path>] [--model <ref>] [--bind <channel[:account]> ...] [--feishu <appId:appSecret>] [--qqbot <appId:appSecret>] [--telegram-bot-token <token>] [--channel-overwrite] [--json] | update --agent <id> [--model <ref>] [--name <text>] [--workspace <path>] [--json] | set-identity --agent <id> [--name <text>] [--emoji <text>] [--theme <text>] [--avatar <path>] [--json] | delete --agent <id> [--json] | help")
}

public func cliRunTasksFlow(args: Array<String>): Int64 {
    let sub = firstArg(args)
    if (sub.isEmpty() || sub == "help") {
        return printLocalFlowUsage(
            "tasks",
            "Inspect and operate task workflows",
            ["metis tasks", "metis tasks list", "metis tasks show", "metis tasks current", "metis tasks next"],
            "list | show | current | next | help"
        )
    }
    if (sub == "list") {
        let obj = JsonObject()
        let entries = ArrayList<JsonValue>()
        entries.add(JsonString("tasks list"))
        entries.add(JsonString("agent --message"))
        entries.add(JsonString("message <text...>"))
        entries.add(JsonString("gateway cron list"))
        obj.put("kind", JsonString("tasks"))
        obj.put("entries", JsonArray(entries))
        putNextSteps(obj, ["metis tasks show", "metis tasks current"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "show") {
        let obj = JsonObject()
        obj.put("kind", JsonString("tasks"))
        obj.put("defaultFlow", JsonString("agent --message"))
        obj.put("cronFlow", JsonString("gateway cron list"))
        obj.put("messageFlow", JsonString("message <text...>"))
        putNextSteps(obj, ["metis tasks current", "metis message preview hello"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "current") {
        let obj = JsonObject()
        obj.put("kind", JsonString("tasks"))
        obj.put("current", JsonString("agent --message"))
        obj.put("next", JsonString("gateway cron list"))
        putNextSteps(obj, ["metis agent --message \"Summarize this repo\"", "metis gateway cron list"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "next") {
        let obj = JsonObject()
        obj.put("kind", JsonString("tasks"))
        obj.put("current", JsonString("agent --message"))
        obj.put("recommended", JsonString("gateway cron list"))
        obj.put("messageFallback", JsonString("message <text...>"))
        putNextSteps(obj, ["metis gateway cron list", "metis message preview hello"])
        return localPrintCommandResult(args, obj)
    }
    printUnknownLocalSubcommand("tasks", sub, "list | show | current | next | help")
}

public func cliRunModelsFlow(args: Array<String>): Int64 {
    let sub = firstArg(args)
    if (sub.isEmpty() || sub == "help") {
        return printLocalFlowUsage(
            "models",
            "Inspect models, providers, and model resolution",
            ["metis models", "metis models list", "metis models current", "metis models providers",
                "metis models auth", "metis models resolve <model>", "metis models set <model>",
                "metis models set-image <model>", "metis models image-fallbacks add <model>",
                "metis models status", "metis models search <term>"],
            "list | current | providers | auth | resolve <model> | set <model> | set-image <model> | image-fallbacks add|remove|clear <model> | status | search <term> | help"
        )
    }
    if (sub == "list") {
        let obj = buildCommandEnvelope("models", "list")
        obj.put("currentModel", JsonString(resolveCliLocalModel()))
        putNextSteps(obj, ["metis models current", "metis models providers"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "current") {
        PrintUtils.printLine(cliCurrentModelRef())
        return CLI_EXIT_OK
    }
    if (sub == "providers") {
        let obj = buildCommandEnvelope("models", "providers")
        obj.put("providers", cliBuildProviderCatalog())
        obj.put("authChoiceGroups", cliBuildModelAuthChoiceGroups())
        putNextSteps(obj, ["metis models current", "metis config defaults"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "auth") {
        let obj = buildCommandEnvelope("models", "auth")
        obj.put("groups", cliBuildModelAuthChoiceGroups())
        obj.put("authChoices", cliBuildModelAuthChoiceCatalog())
        putNextSteps(obj, ["metis models providers", "metis configure"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "resolve") {
        let model = if (argAt(args, 1).isEmpty()) { cliCurrentModelRef() } else { argAt(args, 1) }
        let resolved = MetisConfigManager.canonicalModelRef(model)
        let provider = if (resolved.contains(":")) { resolved.split(":")[0] } else { "ark" }
        let obj = buildCommandEnvelope("models", "resolve")
        obj.put("resolved", JsonString(resolved))
        obj.put("provider", JsonString(provider))
        putNextSteps(obj, ["metis models providers", "metis config defaults"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "set") {
        let model = argAt(args, 1)
        if (model.isEmpty()) {
            return cliReturnMissingArgument("models", "set", "<model>")
        }
        let applied = MetisConfigManager.setPrimaryModelRef(model)
        let obj = buildCommandEnvelope("models", "set")
        obj.put("value", JsonString(applied))
        obj.put("provider", JsonString(cliCurrentProviderId()))
        obj.put("modelConfig", cliBuildCurrentModelConfigView())
        obj.put("runtimeState", cliBuildModelRuntimeStateView())
        obj.put("modelSelection", cliBuildLocalModelSelectionView())
        putNextSteps(obj, ["metis models status", "metis config defaults"])
        return localPrintMutationResult(args, obj, "this updates local model configuration.")
    }
    if (sub == "set-image") {
        let model = argAt(args, 1)
        if (model.isEmpty()) {
            return cliReturnMissingArgument("models", "set-image", "<model>")
        }
        let applied = MetisConfigManager.setImageModelRef(model)
        let obj = buildCommandEnvelope("models", "set-image")
        obj.put("value", JsonString(applied))
        obj.put("modelConfig", cliBuildCurrentModelConfigView())
        putNextSteps(obj, ["metis models status", "metis config defaults"])
        return localPrintMutationResult(args, obj, "this updates local image understanding model configuration.")
    }
    if (sub == "image-fallbacks") {
        let action = argAt(args, 1).toAsciiLower()
        if (action.isEmpty()) {
            return cliReturnMissingArgument("models", "image-fallbacks", "add|remove|clear <model>")
        }
        let current = ArrayList<String>()
        for (item in MetisConfigManager.readImageFallbackModels()) {
            if (!item.trimAscii().isEmpty() && !current.contains(item.trimAscii())) {
                current.add(item.trimAscii())
            }
        }
        if (action == "clear") {
            let applied = MetisConfigManager.setImageFallbackModelRefs([])
            let obj = buildCommandEnvelope("models", "image-fallbacks")
            obj.put("action", JsonString("clear"))
            obj.put("values", JsonArray([]))
            obj.put("count", applied.size.toJsonValue())
            putNextSteps(obj, ["metis models status"])
            return localPrintMutationResult(args, obj, "this clears local image understanding fallback models.")
        }
        let model = argAt(args, 2)
        if (model.isEmpty()) {
            return cliReturnMissingArgument("models", "image-fallbacks ${action}", "<model>")
        }
        let canonical = MetisConfigManager.canonicalModelRef(model).trimAscii()
        if (action == "add") {
            if (!canonical.isEmpty() && !current.contains(canonical)) {
                current.add(canonical)
            }
        } else if (action == "remove") {
            let kept = ArrayList<String>()
            for (item in current) {
                if (item != canonical) {
                    kept.add(item)
                }
            }
            current.clear()
            for (item in kept) {
                current.add(item)
            }
        } else {
            printUnknownLocalSubcommand("models image-fallbacks", action, "add | remove | clear")
            return CLI_EXIT_USAGE_ERROR
        }
        let applied = MetisConfigManager.setImageFallbackModelRefs(current.toArray())
        let values = JsonArray([])
        for (item in applied) {
            values.add(JsonString(item))
        }
        let obj = buildCommandEnvelope("models", "image-fallbacks")
        obj.put("action", JsonString(action))
        obj.put("values", values)
        obj.put("count", applied.size.toJsonValue())
        putNextSteps(obj, ["metis models status"])
        return localPrintMutationResult(args, obj, "this updates local image understanding fallback models.")
    }
    if (sub == "status") {
        let obj = buildCommandEnvelope("models", "status")
        obj.put("currentModel", JsonString(cliCurrentModelRef()))
        obj.put("imageModel", JsonString(CliConfig.imageModelOrEmpty()))
        obj.put("imageFallbackModels", cliImageFallbackModelJson())
        obj.put("provider", JsonString(cliCurrentProviderId()))
        let providerIds = ArrayList<String>()
        for (descriptor in cliModelProviderCatalogDescriptors()) {
            providerIds.add(descriptor.providerId)
        }
        obj.put("availableProviders", JsonString(String.join(providerIds.toArray(), delimiter: ", ")))
        obj.put("modelConfig", cliBuildCurrentModelConfigView())
        obj.put("runtimeState", cliBuildModelRuntimeStateView())
        obj.put("modelSelection", cliBuildLocalModelSelectionView())
        obj.put("authChoices", cliBuildModelAuthChoiceCatalog())
        putNextSteps(obj, ["metis models current", "metis models providers"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "search") {
        let query = joinArgs(args, start: 1)
        if (query.isEmpty()) {
            return cliReturnMissingArgument("models", "search", "<term>")
        }
        let obj = buildCommandEnvelope("models", "search")
        obj.put("query", JsonString(query))
        let matches = ArrayList<JsonValue>()
        matches.add(JsonString(resolveCliLocalModel()))
        matches.add(JsonString("openai:gpt-5.4"))
        obj.put("matches", JsonArray(matches))
        putNextSteps(obj, ["metis models resolve ${query}", "metis models providers"])
        return localPrintCommandResult(args, obj)
    }
    printUnknownLocalSubcommand("models", sub, "list | current | providers | auth | resolve <model> | set <model> | set-image <model> | image-fallbacks add|remove|clear <model> | status | search <term> | help")
}

public func cliRunLogsFlow(args: Array<String>): Int64 {
    let sub = firstArg(args)
    if (sub.isEmpty() || sub == "help") {
        return printLocalFlowUsage(
            "logs",
            "Inspect local CLI and runtime logs",
            ["metis logs", "metis logs path", "metis logs recent", "metis logs current",
                "metis logs tail [file]", "metis logs show [file]"],
            "path | recent | current | tail [file] | show [file] | help"
        )
    }
    if (sub == "path") {
        PrintUtils.printLine(CliConfig.logsDir.toString())
        return CLI_EXIT_OK
    }
    if (sub == "recent" || sub == "current") {
        let obj = buildCommandEnvelope("logs", sub)
        obj.put("logsDir", JsonString(CliConfig.logsDir.toString()))
        obj.put("mode", JsonString(sub))
        let entries = ArrayList<JsonValue>()
        entries.add(JsonString("cli.log"))
        entries.add(JsonString("gateway.log"))
        obj.put("entries", JsonArray(entries))
        putNextSteps(obj, ["metis logs path", "metis system paths"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "tail" || sub == "show") {
        let obj = buildCommandEnvelope("logs", sub)
        obj.put("logsDir", JsonString(CliConfig.logsDir.toString()))
        obj.put("target", JsonString(if (argAt(args, 1).isEmpty()) { "cli.log" } else { argAt(args, 1) }))
        obj.put("preview", JsonString("log output is truncated in local flow mode"))
        putNextSteps(obj, ["metis logs recent", "metis logs path"])
        return localPrintCommandResult(args, obj)
    }
    printUnknownLocalSubcommand("logs", sub, "path | recent | current | tail [file] | show [file] | help")
}

public func cliRunDocsFlow(args: Array<String>): Int64 {
    let sub = firstArg(args)
    if (sub.isEmpty() || sub == "help") {
        return printLocalFlowUsage(
            "docs",
            "Open documentation and inspect docs metadata",
            ["metis docs", "metis docs open", "metis docs topics", "metis docs search <term>",
                "metis docs index", "metis docs path"],
            "open | topics | search <term> | index | path | help"
        )
    }
    if (sub == "open") {
        let obj = buildCommandEnvelope("docs", "open")
        obj.put("url", JsonString("https://docs.metis.ai/cli"))
        putNextSteps(obj, ["metis docs help", "metis acp status"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "topics") {
        let obj = buildCommandEnvelope("docs", "topics")
        let topics = ArrayList<JsonValue>()
        topics.add(JsonString("cli"))
        topics.add(JsonString("gateway"))
        topics.add(JsonString("automation"))
        topics.add(JsonString("agents"))
        obj.put("topics", JsonArray(topics))
        putNextSteps(obj, ["metis docs open", "metis docs search gateway"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "search") {
        let term = joinArgs(args, start: 1)
        if (term.isEmpty()) {
            return cliReturnMissingArgument("docs", "search", "<term>")
        }
        let obj = buildCommandEnvelope("docs", "search")
        obj.put("query", JsonString(term))
        obj.put("url", JsonString("https://docs.metis.ai/cli"))
        putNextSteps(obj, ["metis docs topics", "metis docs open"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "index" || sub == "path") {
        let obj = buildCommandEnvelope("docs", sub)
        obj.put("url", JsonString("https://docs.metis.ai/cli"))
        obj.put("primaryPath", JsonString("/cli"))
        putNextSteps(obj, ["metis docs open", "metis docs topics"])
        return localPrintCommandResult(args, obj)
    }
    printUnknownLocalSubcommand("docs", sub, "open | topics | search <term> | index | path | help")
}

public func cliRunSystemFlow(args: Array<String>): Int64 {
    let sub = firstArg(args)
    if (sub.isEmpty() || sub == "help") {
        return printLocalFlowUsage(
            "system",
            "Inspect workspace paths, environment, and local state",
            ["metis system", "metis system info", "metis system paths", "metis system env",
                "metis system status", "metis system doctor"],
            "info | paths | env | status | doctor | help"
        )
    }
    if (sub == "info") {
        let obj = buildPathSummary("system")
        obj.put("status", JsonString("ok"))
        obj.put("command", JsonString("system"))
        obj.put("subcommand", JsonString("info"))
        obj.put("version", JsonString(CliConfig.version))
        putNextSteps(obj, ["metis system paths", "metis logs path"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "paths") {
        let obj = buildCommandEnvelope("system", "paths")
        obj.put("home", JsonString(CliConfig.dotDir.toString()))
        obj.put("logsDir", JsonString(CliConfig.logsDir.toString()))
        obj.put("configPath", JsonString(MetisPaths.configPath().toString()))
        putNextSteps(obj, ["metis system info", "metis config path"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "env") {
        let obj = buildCommandEnvelope("system", "env")
        obj.put("METIS_HOME", JsonString(CliConfig.dotDir.toString()))
        obj.put("METIS_CJPM_ROOT", JsonString(CliConfig.cwd.toString()))
        putNextSteps(obj, ["metis system paths", "metis docs open"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "status" || sub == "doctor") {
        let obj = buildCommandEnvelope("system", sub)
        obj.put("workspace", JsonString(CliConfig.cwd.toString()))
        obj.put("configPath", JsonString(MetisPaths.configPath().toString()))
        obj.put("logsDir", JsonString(CliConfig.logsDir.toString()))
        putNextSteps(obj, ["metis system info", "metis doctor"])
        return localPrintCommandResult(args, obj)
    }
    printUnknownLocalSubcommand("system", sub, "info | paths | env | status | doctor | help")
}

public func cliRunApprovalsFlow(args: Array<String>): Int64 {
    let sub = firstArg(args)
    if (sub.isEmpty() || sub == "help") {
        return printLocalFlowUsage(
            "approvals",
            "Inspect approval status and policy surfaces",
            ["metis approvals", "metis approvals list", "metis approvals status",
                "metis approvals current", "metis approvals open",
                "metis approvals policy", "metis approvals json"],
            "list | status | current | open | policy | json | help"
        )
    }
    if (sub == "list") {
        let obj = JsonObject()
        let entries = ArrayList<JsonValue>()
        entries.add(JsonString("gateway call devices.policy.audit"))
        entries.add(JsonString("gateway call plugins.approvals"))
        obj.put("kind", JsonString("approvals"))
        obj.put("entries", JsonArray(entries))
        putNextSteps(obj, ["metis approvals status", "metis gateway call plugins.approvals"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "status") {
        let obj = JsonObject()
        obj.put("kind", JsonString("approvals"))
        obj.put("surface", JsonString("gateway"))
        obj.put("recommended", JsonString("metis gateway call plugins.approvals"))
        putNextSteps(obj, ["metis approvals list", "metis gateway call devices.policy.audit"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "current" || sub == "open") {
        let obj = buildCommandEnvelope("approvals", sub)
        obj.put("surface", JsonString("gateway"))
        obj.put("mode", JsonString(sub))
        obj.put("recommended", JsonString("metis gateway call plugins.approvals"))
        putNextSteps(obj, ["metis approvals status", "metis gateway call plugins.approvals"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "policy" || sub == "json") {
        let obj = buildCommandEnvelope("approvals", sub)
        obj.put("surface", JsonString("gateway"))
        obj.put("recommended", JsonString("metis gateway call devices.policy.audit"))
        putNextSteps(obj, ["metis approvals current", "metis gateway call devices.policy.audit"])
        return localPrintCommandResult(args, obj)
    }
    printUnknownLocalSubcommand("approvals", sub, "list | status | current | open | policy | json | help")
}

public func cliRunSandboxFlow(args: Array<String>): Int64 {
    let sub = firstArg(args)
    if (sub.isEmpty() || sub == "help") {
        return printLocalFlowUsage(
            "sandbox",
            "Inspect sandbox mode and sandbox policy",
            ["metis sandbox", "metis sandbox status", "metis sandbox mode",
                "metis sandbox rules", "metis sandbox entry",
                "metis sandbox check", "metis sandbox profile"],
            "status | mode | rules | entry | check | profile | help"
        )
    }
    if (sub == "status" || sub == "mode") {
        let obj = JsonObject()
        obj.put("kind", JsonString("sandbox"))
        obj.put("enabled", JsonBool(false))
        obj.put("entrypoint", JsonString("metis --sandbox --prompt \"...\""))
        putNextSteps(obj, ["metis --sandbox --prompt \"Summarize this repo\"", "metis sandbox help"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "rules") {
        let obj = JsonObject()
        obj.put("kind", JsonString("sandbox"))
        let rules = ArrayList<JsonValue>()
        rules.add(JsonString("workspace-write"))
        rules.add(JsonString("no-network-by-default"))
        rules.add(JsonString("explicit-approval-for-escalation"))
        obj.put("rules", JsonArray(rules))
        putNextSteps(obj, ["metis sandbox status", "metis --sandbox --prompt \"Summarize this repo\""])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "entry") {
        let obj = buildCommandEnvelope("sandbox", "entry")
        obj.put("entrypoint", JsonString("metis --sandbox --prompt \"...\""))
        putNextSteps(obj, ["metis sandbox rules", "metis sandbox status"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "check" || sub == "profile") {
        let obj = buildCommandEnvelope("sandbox", sub)
        obj.put("enabled", JsonBool(false))
        obj.put("profile", JsonString("workspace-write"))
        putNextSteps(obj, ["metis sandbox rules", "metis sandbox status"])
        return localPrintCommandResult(args, obj)
    }
    printUnknownLocalSubcommand("sandbox", sub, "status | mode | rules | entry | check | profile | help")
}

public func cliRunNodeFlow(args: Array<String>): Int64 {
    let sub = firstArg(args)
    if (sub.isEmpty() || sub == "help") {
        return printLocalFlowUsage(
            "node",
            "Inspect one node and its policy state",
            ["metis node", "metis node show", "metis node current",
                "metis node policy", "metis node audit",
                "metis node status", "metis node history"],
            "show | current | policy | audit | status | history | help"
        )
    }
    if (sub == "show" || sub == "current") {
        let obj = JsonObject()
        obj.put("kind", JsonString("node"))
        obj.put("surface", JsonString("gateway"))
        obj.put("recommended", JsonString("metis gateway call nodes.policy"))
        putNextSteps(obj, ["metis nodes list", "metis gateway call nodes.policy.audit"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "policy" || sub == "audit") {
        let obj = buildCommandEnvelope("node", sub)
        obj.put("surface", JsonString("gateway"))
        obj.put("mode", JsonString(sub))
        obj.put("recommended", JsonString("metis gateway call nodes.policy${if (sub == "audit") { ".audit" } else { "" }}"))
        putNextSteps(obj, ["metis node show", "metis nodes list"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "status" || sub == "history") {
        let obj = buildCommandEnvelope("node", sub)
        obj.put("surface", JsonString("gateway"))
        obj.put("recommended", JsonString("metis node current"))
        putNextSteps(obj, ["metis node current", "metis nodes list"])
        return localPrintCommandResult(args, obj)
    }
    printUnknownLocalSubcommand("node", sub, "show | current | policy | audit | status | history | help")
}

public func cliRunQaFlow(args: Array<String>): Int64 {
    let sub = firstArg(args)
    if (sub.isEmpty() || sub == "help") {
        return printLocalFlowUsage(
            "qa",
            "Inspect QA status and quick checks",
            ["metis qa", "metis qa status", "metis qa list", "metis qa run",
                "metis qa scripts", "metis qa report", "metis qa history"],
            "status | list | run | scripts | report | history | help"
        )
    }
    if (sub == "status" || sub == "list") {
        let obj = JsonObject()
        obj.put("kind", JsonString("qa"))
        obj.put("surface", JsonString("local"))
        obj.put("recommended", JsonString("bash scripts/cli-contract-regression.sh"))
        putNextSteps(obj, ["bash scripts/cli-contract-regression.sh", "bash scripts/cli-regression.sh"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "run" || sub == "scripts") {
        let obj = buildCommandEnvelope("qa", sub)
        let scripts = ArrayList<JsonValue>()
        scripts.add(JsonString("bash scripts/cli-contract-regression.sh"))
        scripts.add(JsonString("bash scripts/cli-regression.sh"))
        obj.put("scripts", JsonArray(scripts))
        obj.put("mode", JsonString(sub))
        putNextSteps(obj, ["bash scripts/cli-contract-regression.sh", "bash scripts/cli-regression.sh"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "report" || sub == "history") {
        let obj = buildCommandEnvelope("qa", sub)
        obj.put("surface", JsonString("local"))
        obj.put("recommended", JsonString("bash scripts/cli-contract-regression.sh"))
        putNextSteps(obj, ["metis qa run", "bash scripts/cli-regression.sh"])
        return localPrintCommandResult(args, obj)
    }
    printUnknownLocalSubcommand("qa", sub, "status | list | run | scripts | report | history | help")
}

public func cliRunHooksFlow(args: Array<String>): Int64 {
    let sub = firstArg(args)
    if (sub.isEmpty() || sub == "help") {
        return printLocalFlowUsage(
            "hooks",
            "Inspect hook registration and runbook metadata",
            ["metis hooks", "metis hooks list", "metis hooks status",
                "metis hooks current", "metis hooks runbook",
                "metis hooks validate", "metis hooks open"],
            "list | status | current | runbook | validate | open | help"
        )
    }
    if (sub == "list" || sub == "status") {
        let obj = JsonObject()
        obj.put("kind", JsonString("hooks"))
        obj.put("surface", JsonString("local"))
        obj.put("recommended", JsonString("metis interactive"))
        putNextSteps(obj, ["metis interactive", "metis help hooks"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "current" || sub == "runbook") {
        let obj = buildCommandEnvelope("hooks", sub)
        obj.put("surface", JsonString("local"))
        obj.put("mode", JsonString(sub))
        obj.put("recommended", JsonString("metis interactive"))
        putNextSteps(obj, ["metis hooks status", "metis interactive"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "validate" || sub == "open") {
        let obj = buildCommandEnvelope("hooks", sub)
        obj.put("surface", JsonString("local"))
        obj.put("recommended", JsonString("metis hooks runbook"))
        putNextSteps(obj, ["metis hooks current", "metis hooks runbook"])
        return localPrintCommandResult(args, obj)
    }
    printUnknownLocalSubcommand("hooks", sub, "list | status | current | runbook | validate | open | help")
}

public func cliRunWebhooksFlow(args: Array<String>): Int64 {
    let sub = firstArg(args)
    if (sub.isEmpty() || sub == "help") {
        return printLocalFlowUsage(
            "webhooks",
            "Inspect webhook deliveries and webhook endpoints",
            ["metis webhooks", "metis webhooks list", "metis webhooks status",
                "metis webhooks deliveries", "metis webhooks endpoints",
                "metis webhooks current", "metis webhooks replay"],
            "list | status | deliveries | endpoints | current | replay | help"
        )
    }
    if (sub == "list" || sub == "status") {
        let obj = JsonObject()
        obj.put("kind", JsonString("webhooks"))
        obj.put("surface", JsonString("gateway"))
        obj.put("recommended", JsonString("metis gateway health"))
        putNextSteps(obj, ["metis gateway health", "metis gateway discover"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "deliveries" || sub == "endpoints") {
        let obj = buildCommandEnvelope("webhooks", sub)
        obj.put("surface", JsonString("gateway"))
        obj.put("mode", JsonString(sub))
        putNextSteps(obj, ["metis webhooks status", "metis gateway discover"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "current" || sub == "replay") {
        let obj = buildCommandEnvelope("webhooks", sub)
        obj.put("surface", JsonString("gateway"))
        obj.put("recommended", JsonString("metis webhooks deliveries"))
        putNextSteps(obj, ["metis webhooks deliveries", "metis webhooks endpoints"])
        return localPrintCommandResult(args, obj)
    }
    printUnknownLocalSubcommand("webhooks", sub, "list | status | deliveries | endpoints | current | replay | help")
}

public func cliRunQrFlow(args: Array<String>): Int64 {
    let sub = firstArg(args)
    if (sub.isEmpty() || sub == "help") {
        return printLocalFlowUsage(
            "qr",
            "Inspect QR handoff and pairing payloads",
            ["metis qr", "metis qr show", "metis qr status", "metis qr open",
                "metis qr payload", "metis qr copy", "metis qr link"],
            "show | status | open | payload | copy | link | help"
        )
    }
    if (sub == "show" || sub == "status") {
        let obj = JsonObject()
        obj.put("kind", JsonString("qr"))
        obj.put("surface", JsonString("local"))
        obj.put("recommended", JsonString("metis pairing status"))
        putNextSteps(obj, ["metis pairing status", "metis qr help"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "open" || sub == "payload") {
        let obj = buildCommandEnvelope("qr", sub)
        obj.put("surface", JsonString("local"))
        obj.put("mode", JsonString(sub))
        obj.put("recommended", JsonString("metis pairing status"))
        putNextSteps(obj, ["metis qr show", "metis pairing status"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "copy" || sub == "link") {
        let obj = buildCommandEnvelope("qr", sub)
        obj.put("surface", JsonString("local"))
        obj.put("recommended", JsonString("metis qr payload"))
        putNextSteps(obj, ["metis qr payload", "metis pairing open"])
        return localPrintCommandResult(args, obj)
    }
    printUnknownLocalSubcommand("qr", sub, "show | status | open | payload | copy | link | help")
}

private func cliPairingFlagValue(args: Array<String>, name: String, start!: Int64 = 0): String {
    var i: Int64 = start
    let prefix = "${name}="
    while (i < args.size) {
        let arg = args[i].trimAscii()
        if (arg == name) {
            if (i + 1 < args.size && !args[i + 1].trimAscii().startsWith("--")) {
                return args[i + 1].trimAscii()
            }
            return ""
        }
        if (arg.startsWith(prefix)) {
            return arg[prefix.size..].trimAscii()
        }
        i += 1
    }
    ""
}

private func cliPairingDefaultAccountId(channel: String): String {
    let normalized = channel.trimAscii().toAsciiLower()
    if (normalized == "feishu") {
        try {
            let configured = CliSettingManager.readGatewaySettings().feishu.defaultAccount.trimAscii()
            if (!configured.isEmpty()) {
                return gatewayNormalizePairingAccountId("feishu", configured)
            }
        } catch (_e: Exception) {
            ()
        }
    }
    "default"
}

private func cliPairingResolveAccountId(channel: String, accountId: String): String {
    let normalized = channel.trimAscii().toAsciiLower()
    let raw = accountId.trimAscii()
    if (!raw.isEmpty()) {
        return gatewayNormalizePairingAccountId(normalized, raw)
    }
    cliPairingDefaultAccountId(normalized)
}

private func cliBuildPairingStateObject(
    channel: String,
    accountId: String,
    storeRoot: String,
    pendingRows: Array<JsonObject>,
    approvedSenders: Array<String>,
    recommended: String,
    nextSteps: Array<String>
): JsonObject {
    let pending = JsonArray([])
    for (row in pendingRows) {
        pending.add(row.toJsonValue())
    }
    let approved = JsonArray([])
    for (sender in approvedSenders) {
        approved.add(sender.toJsonValue())
    }
    let obj = JsonObject()
    obj.put("kind", JsonString("pairing"))
    obj.put("surface", JsonString("local"))
    obj.put("channel", JsonString(channel))
    obj.put("accountId", JsonString(accountId))
    obj.put("storeRoot", JsonString(storeRoot))
    obj.put("pending", pending)
    obj.put("approvedSenders", approved)
    obj.put("pendingCount", Int64(pending.size()).toJsonValue())
    obj.put("approvedCount", Int64(approved.size()).toJsonValue())
    obj.put("recommended", JsonString(recommended))
    putNextSteps(obj, nextSteps)
    obj
}

public func cliBuildPairingListResult(
    channel: String,
    accountId!: String = "",
    rootDir!: Path = CliConfig.dotDir
): Option<JsonObject> {
    let normalizedChannel = channel.trimAscii().toAsciiLower()
    if (normalizedChannel == "telegram") {
        let resolvedAccountId = cliPairingResolveAccountId(normalizedChannel, accountId)
        let store = telegramPairingAccountStore(rootDir: rootDir, accountId: resolvedAccountId)
        return Some(cliBuildPairingStateObject(
            "telegram",
            resolvedAccountId,
            store.rootPath().toString(),
            store.pendingRows(),
            store.approvedSenders(),
            "metis pairing approve telegram <CODE>",
            ["metis pairing approve telegram <CODE>", "send Telegram DM again after approval"]
        ))
    }
    if (normalizedChannel == "feishu") {
        let resolvedAccountId = cliPairingResolveAccountId(normalizedChannel, accountId)
        let store = gatewayPairingAccountStore(channel: "feishu", accountId: resolvedAccountId, rootDir: rootDir)
        return Some(cliBuildPairingStateObject(
            "feishu",
            resolvedAccountId,
            store.rootPath().toString(),
            store.pendingRows(),
            store.approvedSenders(),
            "metis pairing approve feishu <CODE> --account ${resolvedAccountId}",
            ["metis pairing approve feishu <CODE> --account ${resolvedAccountId}", "send Feishu DM again after approval"]
        ))
    }
    None<JsonObject>
}

public func cliBuildPairingApproveResult(
    channel: String,
    code: String,
    accountId!: String = "",
    rootDir!: Path = CliConfig.dotDir
): Option<JsonObject> {
    let normalizedChannel = channel.trimAscii().toAsciiLower()
    let normalizedCode = code.trimAscii().toAsciiUpper()
    if (normalizedChannel == "telegram") {
        let resolvedAccountId = cliPairingResolveAccountId(normalizedChannel, accountId)
        let store = telegramPairingAccountStore(rootDir: rootDir, accountId: resolvedAccountId)
        let approved = store.approve(normalizedCode)
        let recommended = if (approved) { "send Telegram DM again" } else { "metis pairing list telegram" }
        let nextSteps = if (approved) {
            ["send Telegram DM again", "metis pairing list telegram"]
        } else {
            ["metis pairing list telegram", "retry with a pending Telegram pairing code"]
        }
        let obj = cliBuildPairingStateObject(
            "telegram",
            resolvedAccountId,
            store.rootPath().toString(),
            store.pendingRows(),
            store.approvedSenders(),
            recommended,
            nextSteps
        )
        obj.put("code", JsonString(normalizedCode))
        obj.put("approved", approved.toJsonValue())
        return Some(obj)
    }
    if (normalizedChannel == "feishu") {
        let resolvedAccountId = cliPairingResolveAccountId(normalizedChannel, accountId)
        let store = gatewayPairingAccountStore(channel: "feishu", accountId: resolvedAccountId, rootDir: rootDir)
        let approved = store.approve(normalizedCode)
        let recommended = if (approved) {
            "send Feishu DM again"
        } else {
            "metis pairing list feishu --account ${resolvedAccountId}"
        }
        let nextSteps = if (approved) {
            ["send Feishu DM again", "metis pairing list feishu --account ${resolvedAccountId}"]
        } else {
            ["metis pairing list feishu --account ${resolvedAccountId}", "retry with a pending Feishu pairing code"]
        }
        let obj = cliBuildPairingStateObject(
            "feishu",
            resolvedAccountId,
            store.rootPath().toString(),
            store.pendingRows(),
            store.approvedSenders(),
            recommended,
            nextSteps
        )
        obj.put("code", JsonString(normalizedCode))
        obj.put("approved", approved.toJsonValue())
        return Some(obj)
    }
    None<JsonObject>
}

public func cliRunPairingFlow(args: Array<String>): Int64 {
    let sub = firstArg(args)
    if (sub.isEmpty() || sub == "help") {
        return printLocalFlowUsage(
            "pairing",
            "Inspect pairing state and pairing handoff",
            ["metis pairing", "metis pairing status", "metis pairing list",
                "metis pairing list feishu --account <id>",
                "metis pairing approve telegram <CODE>",
                "metis pairing approve feishu <CODE> --account <id>", "metis pairing current", "metis pairing open",
                "metis pairing code", "metis pairing sessions"],
            "status | list | approve | current | open | code | sessions | help"
        )
    }
    if (sub == "status" || sub == "list") {
        let channel = argAt(args, 1).trimAscii().toAsciiLower()
        if (channel == "telegram" || channel == "feishu") {
            let accountId = cliPairingFlagValue(args, "--account", start: 2)
            match (cliBuildPairingListResult(channel, accountId: accountId)) {
                case Some(obj) => return localPrintCommandResult(args, obj)
                case None => ()
            }
        }
        let obj = JsonObject()
        obj.put("kind", JsonString("pairing"))
        obj.put("surface", JsonString("local"))
        obj.put("recommended", JsonString("metis qr show"))
        putNextSteps(obj, ["metis pairing list telegram", "metis pairing list feishu --account <id>", "metis pairing help"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "approve") {
        let channel = argAt(args, 1).trimAscii().toAsciiLower()
        if (channel != "telegram" && channel != "feishu") {
            PrintUtils.printLine("Unsupported pairing approval target: ${channel}")
            PrintUtils.printLine("Supported approval targets: telegram, feishu")
            return CLI_EXIT_USAGE_ERROR
        }
        let code = argAt(args, 2).trimAscii().toAsciiUpper()
        if (code.isEmpty()) {
            PrintUtils.printLine("Usage: metis pairing approve telegram <CODE>")
            PrintUtils.printLine("       metis pairing approve feishu <CODE> --account <id>")
            return CLI_EXIT_USAGE_ERROR
        }
        let accountId = cliPairingFlagValue(args, "--account", start: 3)
        match (cliBuildPairingApproveResult(channel, code, accountId: accountId)) {
            case Some(obj) =>
                let targetLabel = if (channel == "feishu") { "Feishu" } else { "Telegram" }
                return localPrintMutationResult(args, obj, "this approves a pending ${targetLabel} sender in local pairing state.")
            case None => ()
        }
        PrintUtils.printLine("Unsupported pairing approval target: ${channel}")
        PrintUtils.printLine("Supported approval targets: telegram, feishu")
        return CLI_EXIT_USAGE_ERROR
    }
    if (sub == "current" || sub == "open") {
        let obj = buildCommandEnvelope("pairing", sub)
        obj.put("surface", JsonString("local"))
        obj.put("mode", JsonString(sub))
        obj.put("recommended", JsonString("metis qr show"))
        putNextSteps(obj, ["metis pairing status", "metis qr show"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "code" || sub == "sessions") {
        let obj = buildCommandEnvelope("pairing", sub)
        obj.put("surface", JsonString("local"))
        obj.put("recommended", JsonString("metis qr open"))
        putNextSteps(obj, ["metis pairing current", "metis qr open"])
        return localPrintCommandResult(args, obj)
    }
    printUnknownLocalSubcommand("pairing", sub, "status | list | approve | current | open | code | sessions | help")
}

public func cliRunDaemonFlow(args: Array<String>): Int64 {
    let sub = firstArg(args)
    if (sub.isEmpty() || sub == "help") {
        return printLocalFlowUsage(
            "daemon",
            "Inspect daemon state and daemon restart hints",
            ["metis daemon", "metis daemon status", "metis daemon info",
                "metis daemon logs", "metis daemon pid",
                "metis daemon socket", "metis daemon restart"],
            "status | info | logs | pid | socket | restart | help"
        )
    }
    if (sub == "status" || sub == "info") {
        let obj = JsonObject()
        obj.put("kind", JsonString("daemon"))
        obj.put("surface", JsonString("local"))
        obj.put("recommended", JsonString("metis gateway status"))
        putNextSteps(obj, ["metis gateway status", "metis daemon help"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "logs" || sub == "pid") {
        let obj = buildCommandEnvelope("daemon", sub)
        obj.put("surface", JsonString("local"))
        obj.put("mode", JsonString(sub))
        putNextSteps(obj, ["metis daemon status", "metis gateway status"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "socket" || sub == "restart") {
        let obj = buildCommandEnvelope("daemon", sub)
        obj.put("surface", JsonString("local"))
        obj.put("recommended", JsonString("metis gateway restart"))
        putNextSteps(obj, ["metis daemon status", "metis gateway restart"])
        return localPrintCommandResult(args, obj)
    }
    printUnknownLocalSubcommand("daemon", sub, "status | info | logs | pid | socket | restart | help")
}

public func cliRunAcpFlow(args: Array<String>): Int64 {
    let sub = firstArg(args)
    if (sub.isEmpty() || sub == "help") {
        return printLocalFlowUsage(
            "acp",
            "Inspect ACP runtime metadata",
            ["metis acp", "metis acp status", "metis acp list",
                "metis acp current", "metis acp docs",
                "metis acp mode", "metis acp runtime"],
            "status | list | current | docs | mode | runtime | help"
        )
    }
    if (sub == "status" || sub == "list") {
        let obj = JsonObject()
        obj.put("kind", JsonString("acp"))
        obj.put("surface", JsonString("local"))
        obj.put("recommended", JsonString("metis docs open"))
        putNextSteps(obj, ["metis docs open", "metis acp help"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "current" || sub == "docs") {
        let obj = buildCommandEnvelope("acp", sub)
        obj.put("surface", JsonString("local"))
        obj.put("mode", JsonString(sub))
        obj.put("recommended", JsonString("metis docs open"))
        putNextSteps(obj, ["metis acp status", "metis docs open"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "mode" || sub == "runtime") {
        let obj = buildCommandEnvelope("acp", sub)
        obj.put("surface", JsonString("local"))
        obj.put("recommended", JsonString("metis acp current"))
        putNextSteps(obj, ["metis acp current", "metis docs open"])
        return localPrintCommandResult(args, obj)
    }
    printUnknownLocalSubcommand("acp", sub, "status | list | current | docs | mode | runtime | help")
}

public func cliRunNodesFlow(args: Array<String>): Int64 {
    let sub = firstArg(args)
    if (sub.isEmpty() || sub == "help") {
        return printLocalFlowUsage(
            "nodes",
            "Inspect node scheduling and node policy",
            ["metis nodes", "metis nodes list", "metis nodes policy",
                "metis nodes audit", "metis nodes status", "metis nodes current"],
            "list | policy | audit | status | current | help"
        )
    }
    if (sub == "list") {
        let obj = JsonObject()
        obj.put("kind", JsonString("nodes"))
        obj.put("surface", JsonString("gateway"))
        obj.put("recommended", JsonString("metis gateway call nodes.policy.audit"))
        putNextSteps(obj, ["metis node show", "metis gateway call nodes.policy.audit"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "policy" || sub == "audit") {
        let obj = buildCommandEnvelope("nodes", sub)
        obj.put("surface", JsonString("gateway"))
        obj.put("mode", JsonString(sub))
        obj.put("recommended", JsonString("metis gateway call nodes.policy${if (sub == "audit") { ".audit" } else { "" }}"))
        putNextSteps(obj, ["metis nodes list", "metis node show"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "status" || sub == "current") {
        let obj = buildCommandEnvelope("nodes", sub)
        obj.put("surface", JsonString("gateway"))
        obj.put("recommended", JsonString("metis nodes policy"))
        putNextSteps(obj, ["metis nodes policy", "metis node current"])
        return localPrintCommandResult(args, obj)
    }
    printUnknownLocalSubcommand("nodes", sub, "list | policy | audit | status | current | help")
}

public func cliRunDevicesFlow(args: Array<String>): Int64 {
    let sub = firstArg(args)
    if (sub.isEmpty() || sub == "help") {
        return printLocalFlowUsage(
            "devices",
            "Inspect device state and device policy",
            ["metis devices", "metis devices list", "metis devices policy",
                "metis devices audit", "metis devices status", "metis devices current"],
            "list | policy | audit | status | current | help"
        )
    }
    if (sub == "list") {
        let obj = JsonObject()
        obj.put("kind", JsonString("devices"))
        obj.put("surface", JsonString("gateway"))
        obj.put("recommended", JsonString("metis gateway call devices.policy.audit"))
        putNextSteps(obj, ["metis approvals status", "metis gateway call devices.policy.audit"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "policy" || sub == "audit") {
        let obj = buildCommandEnvelope("devices", sub)
        obj.put("surface", JsonString("gateway"))
        obj.put("mode", JsonString(sub))
        obj.put("recommended", JsonString("metis gateway call devices.policy${if (sub == "audit") { ".audit" } else { "" }}"))
        putNextSteps(obj, ["metis devices list", "metis approvals status"])
        return localPrintCommandResult(args, obj)
    }
    if (sub == "status" || sub == "current") {
        let obj = buildCommandEnvelope("devices", sub)
        obj.put("surface", JsonString("gateway"))
        obj.put("recommended", JsonString("metis devices policy"))
        putNextSteps(obj, ["metis devices policy", "metis approvals status"])
        return localPrintCommandResult(args, obj)
    }
    printUnknownLocalSubcommand("devices", sub, "list | policy | audit | status | current | help")
}
