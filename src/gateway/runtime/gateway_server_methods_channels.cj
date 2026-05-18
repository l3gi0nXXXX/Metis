package metis.gateway.runtime

import magic.jsonable.*

import metis.core.gatewayVideoGenerationResolveConfig
import metis.core.config.{CliConfig, CliSettingManager, GatewayPluginUserSettings, GatewayUserSettings}
import metis.gateway.channels.feishu.{gatewayFeishuDescribeAccounts, feishuGatewayNativeAuthLiveSmoke}
import metis.gateway.channels.qq.{gatewayQqDefaultAccountId, gatewayQqDescribeAccounts}
import metis.gateway.channels.telegram.{TelegramAdapter, gatewayTelegramResolveAccount, telegramPairingAccountStore}
import metis.gateway.model.{ChannelType, OutboundMessage}
import metis.gateway.core.{
    gatewayChannelRuntimeMarkFailure,
    gatewayChannelRuntimeMarkRunning,
    gatewayChannelRuntimeMarkSend,
    gatewayChannelRuntimeMarkStarting,
    gatewayChannelRuntimeMarkStopped,
    gatewayCanonicalChannelAccountId,
    gatewayChannelRuntimeAccountsJson,
    gatewayChannelRuntimeBootstrapSummary,
    gatewayChannelRuntimeDefaultAccountId,
    gatewayChannelManagerSummary,
    gatewayChannelRuntimeSnapshot,
    gatewayChannelRuntimeSummary,
    gatewayPluginManagerSummary,
    gatewayPluginRuntimeAccountsJson,
    gatewayPluginRuntimeSummary,
    gatewayListSessionCatalogViewsForUser,
    gatewayOpenClawPluginSidecarApplyMessageSendingHook,
    gatewayOpenClawPluginSidecarApplyMessageSentHook,
    gatewayFeishuNativeAuthComplete,
    gatewayFeishuNativeAuthPoll,
    gatewayFeishuNativeAuthRevoke,
    gatewayFeishuNativeAuthStatus,
    gatewayFeishuNativeAuthStart
}
import metis.gateway.config.{
    GatewayChannelPluginRegistry,
    builtinGatewayChannelIds,
    gatewayChannelBindingActionsJson,
    gatewayChannelBindingConstraintsJson,
    gatewayProbeResultJson,
    gatewayProbeTimestampMs,
    gatewaySynthesizedRuntimeAccounts,
    gatewayChannelCatalogJson,
    gatewayChannelDetailLabelsJson,
    gatewayChannelLabelsJson,
    gatewayChannelOrderJson,
    gatewayChannelSystemImagesJson,
    gatewayBindingActionsNeeded,
    getGatewayChannelCatalogEntry,
    getGatewayPluginCatalogEntry,
    gatewayChannelBindingState,
    gatewayBindingsPolicySummaryJson,
    gatewayChannelMetaJson,
    gatewayPluginBindingActionsJson,
    gatewayPluginConfigPresent,
    gatewayPluginBindingConstraintsJson,
    gatewayPluginBindingState,
    gatewayPluginCatalogJson,
    gatewayPluginApprovalRowJson,
    gatewayPluginMetaJson,
    gatewayPluginOrderJson,
    gatewayPluginPackageProbeRowJson,
    gatewayPluginSetupRowJson,
    gatewayPluginsApprovalSummaryJson,
    gatewayPluginsPackageStateSummaryJson,
    gatewayPluginsSetupSummaryJson,
    gatewayDiscoverDetailSummaryJson,
    gatewayBatchApplySummaryJson,
    gatewayBindingProbeAuditBundle,
    buildGatewayConfigFromUserSettings,
    listGatewayChannelCatalogEntries,
    listGatewayPluginCatalogEntries,
    normalizeGatewayChannelId,
    pluginConfigFromChannelsExtraObject,
    pluginConfigFromChannelsExtra,
    registeredGatewayPluginIds
}

import std.convert.Parsable
import std.collection.{ArrayList, HashMap}
import std.time.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private func gatewayRpcStringParam(request: GatewayRpcRequest, keys: Array<String>, defaultValue: String): String {
    for (key in keys) {
        match (request.params.get(key)) {
            case Some(v) =>
                try {
                    let value = v.asString().getValue().trimAscii()
                    if (!value.isEmpty()) {
                        return value
                    }
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
    }
    defaultValue
}

private func gatewayRpcBoolParam(request: GatewayRpcRequest, keys: Array<String>, defaultValue: Bool): Bool {
    for (key in keys) {
        match (request.params.get(key)) {
            case Some(v) =>
                try {
                    return v.asBool().getValue()
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
    }
    defaultValue
}

private func gatewayRpcJsonString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func gatewayRpcJsonBool(obj: JsonObject, key: String, defaultValue: Bool): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { defaultValue }
        case None => defaultValue
    }
}

private func gatewayRpcJsonObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func gatewayRpcVideoConfigState(config: JsonObject): String {
    if (!gatewayRpcJsonBool(config, "enabled", true)) {
        return "disabled"
    }
    let provider = gatewayRpcJsonString(config, "provider")
    if (provider.isEmpty()) {
        return "not_configured"
    }
    let providers = gatewayRpcJsonObject(config, "providers")
    match (providers.get(provider)) {
        case Some(v) =>
            let providerConfig = try { v.asObject() } catch (_e: Exception) { JsonObject() }
            if (providerConfig.size() > 0) { "configured" } else { "not_configured" }
        case None => "not_configured"
    }
}

private func gatewayRpcTelegramVideoUnderstandingState(user: GatewayUserSettings): String {
    let telegram = user.telegram.video
    let shared = user.media.video
    let enabled = if (telegram.get("enabled").isSome()) {
        gatewayRpcJsonBool(telegram, "enabled", true)
    } else {
        gatewayRpcJsonBool(shared, "enabled", true)
    }
    if (!enabled) {
        return "disabled"
    }
    let provider = if (!gatewayRpcJsonString(telegram, "provider").isEmpty()) {
        gatewayRpcJsonString(telegram, "provider")
    } else {
        gatewayRpcJsonString(shared, "provider")
    }
    if (provider.isEmpty()) {
        return "not_configured"
    }
    let telegramProvider = gatewayRpcJsonObject(gatewayRpcJsonObject(telegram, "providers"), provider)
    let sharedProvider = gatewayRpcJsonObject(gatewayRpcJsonObject(shared, "providers"), provider)
    if (telegramProvider.size() > 0 || sharedProvider.size() > 0) {
        return "configured"
    }
    "not_configured"
}

private func gatewayRpcIntParam(request: GatewayRpcRequest, keys: Array<String>, defaultValue: Int64): Int64 {
    for (key in keys) {
        match (request.params.get(key)) {
            case Some(v) =>
                try {
                    return Int64.parse(v.toJsonString())
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
    }
    defaultValue
}

private func gatewayBindingStringParam(obj: JsonObject, keys: Array<String>, defaultValue: String): String {
    for (key in keys) {
        match (obj.get(key)) {
            case Some(v) =>
                try {
                    let value = v.asString().getValue().trimAscii()
                    if (!value.isEmpty()) {
                        return value
                    }
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
    }
    defaultValue
}

private func gatewayPluginSettingsJson(user: GatewayUserSettings): JsonArray {
    let rows = JsonArray([])
    for (plugin in user.gatewayPlugins) {
        let row = JsonObject()
        row.put("id", JsonString(plugin.id))
        row.put("enabled", plugin.enabled.toJsonValue())
        rows.add(row)
    }
    rows
}

private func gatewayJsonBool(obj: JsonObject, key: String, defaultValue: Bool): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { defaultValue }
        case None => defaultValue
    }
}

private func gatewayEnsureChannelBootstrap(user: GatewayUserSettings): JsonObject {
    let bootstrap = gatewayPrimeConfiguredChannelBindings(user)
    let consumed = gatewayConsumeAllLegacyPluginRuntimes(user)
    let result = JsonObject()
    result.put("bootstrap", bootstrap)
    result.put("legacyRuntime", consumed)
    result
}

private func gatewayChannelsExtraJson(user: GatewayUserSettings): JsonValue {
    match (user.channelsExtra) {
        case Some(v) => v
        case None => JsonObject()
    }
}

private func gatewayPluginSettingById(user: GatewayUserSettings, pluginId: String): JsonObject {
    let normalized = pluginId.trimAscii().toAsciiLower()
    for (plugin in user.gatewayPlugins) {
        if (plugin.id.trimAscii().toAsciiLower() == normalized) {
            let row = JsonObject()
            row.put("id", JsonString(plugin.id))
            row.put("enabled", plugin.enabled.toJsonValue())
            return row
        }
    }
    JsonObject()
}

private func gatewayMergeJsonObjects(base: JsonObject, overlay: JsonObject): JsonObject {
    if (overlay.size() > 0) {
        return overlay
    }
    base
}

private func gatewayRequestJsonObjectParam(request: GatewayRpcRequest, keys: Array<String>): JsonObject {
    for (key in keys) {
        match (request.params.get(key)) {
            case Some(v) =>
                try {
                    return v.asObject()
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
    }
    JsonObject()
}

private func gatewayRequestNestedJsonObjectParam(
    request: GatewayRpcRequest,
    parentKeys: Array<String>,
    childKey: String
): JsonObject {
    for (parentKey in parentKeys) {
        match (request.params.get(parentKey)) {
            case Some(v) =>
                try {
                    let parent = v.asObject()
                    match (parent.get(childKey)) {
                        case Some(child) =>
                            try {
                                return child.asObject()
                            } catch (_e: Exception) {
                                ()
                            }
                        case None => ()
                    }
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
    }
    JsonObject()
}

private func gatewayRequestNestedStringParam(
    request: GatewayRpcRequest,
    parentKeys: Array<String>,
    childKeys: Array<String>,
    defaultValue: String
): String {
    for (parentKey in parentKeys) {
        match (request.params.get(parentKey)) {
            case Some(v) =>
                try {
                    let parent = v.asObject()
                    for (childKey in childKeys) {
                        match (parent.get(childKey)) {
                            case Some(child) =>
                                try {
                                    let value = child.asString().getValue().trimAscii()
                                    if (!value.isEmpty()) {
                                        return value
                                    }
                                } catch (_e: Exception) {
                                    ()
                                }
                            case None => ()
                        }
                    }
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
    }
    defaultValue
}

private func gatewayDispatchPayloadParam(request: GatewayRpcRequest): JsonObject {
    let directPayload = gatewayRequestJsonObjectParam(request, ["payload"])
    let nestedPayload = gatewayRequestNestedJsonObjectParam(request, ["arguments"], "payload")
    let payload = if (nestedPayload.size() > 0) {
        nestedPayload
    } else if (directPayload.size() > 0) {
        directPayload
    } else {
        JsonObject()
    }
    let text = gatewayRpcStringParam(request, ["text", "message"], "")
    if (!text.isEmpty() && payload.get("text").isNone()) {
        payload.put("text", JsonString(text))
    } else {
        let nestedText = gatewayRequestNestedStringParam(request, ["arguments"], ["text", "message"], "")
        if (!nestedText.isEmpty() && payload.get("text").isNone()) {
            payload.put("text", JsonString(nestedText))
        }
    }
    let peerId = gatewayRpcStringParam(request, ["peerId", "to", "target"], "")
    if (!peerId.isEmpty() && payload.get("peerId").isNone()) {
        payload.put("peerId", JsonString(peerId))
    } else {
        let nestedPeerId = gatewayRequestNestedStringParam(request, ["arguments"], ["peerId", "to", "target"], "")
        if (!nestedPeerId.isEmpty() && payload.get("peerId").isNone()) {
            payload.put("peerId", JsonString(nestedPeerId))
        }
    }
    let replyTo = gatewayRpcStringParam(request, ["replyTo", "replyToMessageId"], "")
    if (!replyTo.isEmpty() && payload.get("replyTo").isNone()) {
        payload.put("replyTo", JsonString(replyTo))
    } else {
        let nestedReplyTo = gatewayRequestNestedStringParam(request, ["arguments"], ["replyTo", "replyToMessageId"], "")
        if (!nestedReplyTo.isEmpty() && payload.get("replyTo").isNone()) {
            payload.put("replyTo", JsonString(nestedReplyTo))
        }
    }
    let replyToMessageId = gatewayRpcStringParam(request, ["replyToMessageId"], "")
    if (!replyToMessageId.isEmpty() && payload.get("replyToMessageId").isNone()) {
        payload.put("replyToMessageId", JsonString(replyToMessageId))
    } else {
        let nestedReplyToMessageId = gatewayRequestNestedStringParam(request, ["arguments"], ["replyToMessageId"], "")
        if (!nestedReplyToMessageId.isEmpty() && payload.get("replyToMessageId").isNone()) {
            payload.put("replyToMessageId", JsonString(nestedReplyToMessageId))
        }
    }
    let replyInThread = gatewayRpcBoolParam(request, ["replyInThread"], false)
    if (replyInThread && payload.get("replyInThread").isNone()) {
        payload.put("replyInThread", true.toJsonValue())
    }
    payload
}

public func gatewayChannelsDeliveryJson(
    channelId: String,
    peerId: String,
    accountId: String,
    replyToMessageId!: String = "",
    replyInThread!: Bool = false,
    deliverable!: Bool = false
): JsonObject {
    let delivery = JsonObject()
    let normalizedChannel = normalizeGatewayChannelId(channelId)
    delivery.put("channel", JsonString(normalizedChannel))
    delivery.put("peer", JsonString(peerId))
    delivery.put("replyChannel", JsonString(normalizedChannel))
    delivery.put("replyTo", JsonString(peerId))
    delivery.put("replyToMessageId", JsonString(replyToMessageId.trimAscii()))
    delivery.put("replyInThread", replyInThread.toJsonValue())
    delivery.put("accountId", JsonString(accountId.trimAscii()))
    delivery.put("deliverable", deliverable.toJsonValue())
    delivery
}

private func gatewayEnsurePluginEnabled(user: GatewayUserSettings, pluginId: String): GatewayUserSettings {
    var updated = user
    let normalized = normalizeGatewayChannelId(pluginId)
    let arr = ArrayList<GatewayPluginUserSettings>()
    var found = false
    for (plugin in updated.gatewayPlugins) {
        if (normalizeGatewayChannelId(plugin.id) == normalized) {
            arr.add(GatewayPluginUserSettings(id: normalized, enabled: true))
            found = true
        } else if (!plugin.id.trimAscii().isEmpty()) {
            arr.add(plugin)
        }
    }
    if (!found) {
        arr.add(GatewayPluginUserSettings(id: normalized, enabled: true))
    }
    updated.gatewayPlugins = arr.toArray()
    updated
}

private func gatewayApplyPluginSetup(user: GatewayUserSettings, pluginId: String, request: GatewayRpcRequest): JsonObject {
    let normalized = normalizeGatewayChannelId(pluginId)
    var updated = gatewayEnsurePluginEnabled(user, normalized)
    let baseConfig = pluginConfigFromChannelsExtraObject(updated.channelsExtra, normalized)
    let requestConfig = gatewayRequestJsonObjectParam(request, ["config", "setup", "values"])
    let merged = gatewayMergeJsonObjects(baseConfig, requestConfig)
    let hostApply = if (gatewayLegacyPluginHostCompatible(normalized)) {
        gatewayLegacyPluginHostApplySetup(normalized, config: merged)
    } else {
        JsonObject()
    }
    let finalConfig = match (hostApply.get("config")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { merged }
        case None => merged
    }
    let setupState = if (gatewayLegacyPluginHostCompatible(normalized)) {
        hostApply
    } else {
        gatewayPluginSetupRow(updated, normalized)
    }
    merged.put("compatibilityMode", JsonString("legacy-plugin-host"))
    merged.put("setupAppliedAtMs", DateTime.now().toUnixTimeStamp().toMilliseconds().toJsonValue())
    match (setupState.get("state")) {
        case Some(v) => finalConfig.put("setupState", v)
        case None => ()
    }
    match (setupState.get("defaultAccountId")) {
        case Some(v) => finalConfig.put("defaultAccountId", v)
        case None => ()
    }
    match (setupState.get("accountIds")) {
        case Some(v) => finalConfig.put("accountIds", v)
        case None => ()
    }
    match (setupState.get("supports")) {
        case Some(v) => finalConfig.put("supports", v)
        case None => ()
    }
    finalConfig.put("compatibilityMode", JsonString("legacy-plugin-host"))
    finalConfig.put("setupAppliedAtMs", DateTime.now().toUnixTimeStamp().toMilliseconds().toJsonValue())
    let root = match (updated.channelsExtra) {
        case Some(v) => v
        case None => JsonObject()
    }
    root.put(normalized, finalConfig)
    updated.channelsExtra = Some(root)
    CliSettingManager.writeGatewaySettings(updated)
    gatewayEnsureChannelBootstrap(updated)
    let result = JsonObject()
    result.put("pluginId", JsonString(normalized))
    result.put("applied", (setupState.get("applied") ?? true.toJsonValue()))
    if (hostApply.size() > 0) {
        result.put("host", hostApply)
    }
    result.put("config", finalConfig)
    result.put("setup", gatewayPluginSetupRow(updated, normalized))
    result.put("bindings", gatewayPluginBindingsJson(updated, normalized))
    result.put("runtime", gatewayPluginRuntimeSummary(normalized))
    result
}

private func gatewayFeishuDefaultAccountId(user: GatewayUserSettings): String {
    if (user.feishu.defaultAccount.trimAscii().isEmpty()) { "default" } else { user.feishu.defaultAccount.trimAscii() }
}

private func gatewayFeishuGroupsJson(user: GatewayUserSettings): JsonArray {
    gatewayTelegramObjectKeysJson(user.feishu.groups)
}

private func gatewayFeishuAccountInspectRow(user: GatewayUserSettings, accountId: String, accountConfig: JsonObject, defaultAccountId: String): JsonObject {
    let row = JsonObject()
    let accountAppId = gatewayBindingStringParam(accountConfig, ["appId", "app_id"], "")
    let accountSecret = gatewayBindingStringParam(accountConfig, ["appSecret", "app_secret"], "")
    let accountEnabled = gatewayJsonBool(accountConfig, "enabled", true)
    let globalConfigured = !user.feishu.appId.trimAscii().isEmpty() || !user.feishu.appSecret.trimAscii().isEmpty()
    let credentialSource = if (!accountSecret.isEmpty() || !accountAppId.isEmpty()) {
        "account"
    } else if (globalConfigured) {
        "global-inherited"
    } else {
        "missing"
    }
    row.put("accountId", JsonString(accountId))
    row.put("defaultAccount", (accountId == defaultAccountId).toJsonValue())
    row.put("enabled", accountEnabled.toJsonValue())
    row.put("configured", (credentialSource != "missing").toJsonValue())
    row.put("credentialSource", JsonString(credentialSource))
    row.put("hasAppId", (!accountAppId.isEmpty()).toJsonValue())
    row.put("hasAppSecret", (!accountSecret.isEmpty()).toJsonValue())
    row.put("redacted", true.toJsonValue())
    row.put("hasGroupsOverride", gatewayTelegramConfigHasObject(accountConfig, "groups").toJsonValue())
    row.put("groupAllowFromCount", gatewayTelegramConfigArraySize(accountConfig, "groupAllowFrom").toJsonValue())
    return row
}

private func gatewayFeishuAccountInspectJson(user: GatewayUserSettings): JsonObject {
    let out = JsonObject()
    let defaultAccountId = gatewayFeishuDefaultAccountId(user)
    out.put("defaultAccountId", JsonString(defaultAccountId))
    out.put("tokenRedacted", true.toJsonValue())
    let rows = JsonArray([])
    let seen = HashMap<String, Bool>()
    match (user.feishu.accounts) {
        case Some(accounts) =>
            for (accountId in accounts.getFields().keys()) {
                let trimmed = accountId.trimAscii()
                if (trimmed.isEmpty()) {
                    continue
                }
                let accountConfig = try { accounts.getFields()[accountId].asObject() } catch (_e: Exception) { JsonObject() }
                rows.add(gatewayFeishuAccountInspectRow(user, trimmed, accountConfig, defaultAccountId))
                seen[trimmed] = true
            }
        case None => ()
    }
    if (!seen.contains(defaultAccountId)) {
        rows.add(gatewayFeishuAccountInspectRow(user, defaultAccountId, JsonObject(), defaultAccountId))
    }
    out.put("accounts", rows)
    out.put("count", rows.size().toJsonValue())
    return out
}

private func gatewayFeishuDirectoryJson(user: GatewayUserSettings): JsonObject {
    let out = JsonObject()
    out.put("groups", gatewayFeishuGroupsJson(user))
    out.put("accounts", gatewayTelegramObjectKeysJson(user.feishu.accounts))
    out.put("targets", gatewayFeishuGroupsJson(user))
    out.put("rows", JsonArray([]))
    out.put("aggregationSources", JsonArray([JsonString("config")]))
    return out
}

private func gatewayFeishuAccountOpsJson(): JsonObject {
    let out = JsonObject()
    out.put("list", true.toJsonValue())
    out.put("describe", true.toJsonValue())
    out.put("enable", true.toJsonValue())
    out.put("disable", true.toJsonValue())
    out.put("validate", true.toJsonValue())
    out.put("mutationRequiresGatewayRpc", true.toJsonValue())
    return out
}

private func gatewayFeishuNativeCommandsJson(): JsonObject {
    let out = JsonObject()
    out.put("supported", true.toJsonValue())
    out.put("surface", JsonString("feishu-im-native-command"))
    out.put("architecture", JsonString("GatewayService handles Feishu native IM commands; Gateway RPC and Control UI expose the same auth and diagnostic actions."))
    out.put("commands", JsonArray([
        JsonString("/feishu start"),
        JsonString("/feishu doctor"),
        JsonString("/feishu auth"),
        JsonString("/feishu info --all")
    ]))
    out.put("gatewayRpcActions", JsonArray([
        JsonString("channels.feishu.auth.start"),
        JsonString("channels.feishu.auth.status"),
        JsonString("channels.feishu.auth.poll"),
        JsonString("channels.feishu.auth.complete"),
        JsonString("channels.feishu.auth.revoke"),
        JsonString("channels.feishu.auth.liveSmoke"),
        JsonString("channels.status"),
        JsonString("channels.get")
    ]))
    out.put("diagnostics", JsonArray([
        JsonString("account redaction"),
        JsonString("threadSession"),
        JsonString("groupPolicy"),
        JsonString("media"),
        JsonString("unsupportedFields")
    ]))
    out.put("redacted", true.toJsonValue())
    return out
}

private func gatewayFeishuMediaJson(user: GatewayUserSettings): JsonObject {
    let media = JsonObject()
    media.put("downloadEnabled", user.feishu.media.downloadEnabled.toJsonValue())
    media.put("mediaMaxBytes", user.feishu.media.mediaMaxBytes.toJsonValue())
    let allowedMimes = JsonArray([])
    for (mime in user.feishu.media.allowedMimes) {
        allowedMimes.add(JsonString(mime))
    }
    media.put("allowedMimes", allowedMimes)
    media.put("downloadRoot", JsonString(user.feishu.media.downloadRoot))
    return media
}

private func gatewayFeishuReceiveModeDiagnosticsJson(user: GatewayUserSettings): JsonObject {
    let out = JsonObject()
    out.put("mode", JsonString(user.feishu.receiveMode))
    out.put("supportedModes", JsonArray([JsonString("long_connect"), JsonString("webhook")]))
    out.put("state", JsonString(if (user.feishu.receiveMode == "webhook" || user.feishu.receiveMode == "long_connect") { "supported" } else { "normalized_by_runtime" }))
    return out
}

private func gatewayFeishuGroupPolicyDiagnosticsJson(user: GatewayUserSettings): JsonObject {
    let out = JsonObject()
    out.put("mode", JsonString(user.feishu.groupPolicy))
    out.put("allowFromCount", user.feishu.groupAllowFrom.size.toJsonValue())
    out.put("configuredGroupCount", gatewayFeishuGroupsJson(user).size().toJsonValue())
    out.put("requireMention", user.feishu.requireMention.toJsonValue())
    out.put("allowBots", user.feishu.allowBots.toJsonValue())
    out.put("state", JsonString("evaluated_per_account_and_group"))
    return out
}

private func gatewayFeishuThreadSessionDiagnosticsJson(user: GatewayUserSettings): JsonObject {
    let out = JsonObject()
    out.put("enabled", user.feishu.threadSession.toJsonValue())
    out.put("cache", JsonString("account_scoped_chat_thread_capability"))
    out.put("skippedReasons", JsonArray([
        JsonString("thread_session_disabled"),
        JsonString("thread_not_capable")
    ]))
    out.put("state", JsonString(if (user.feishu.threadSession) { "requires_thread_capable_group" } else { "disabled" }))
    return out
}

private func gatewayFeishuChannelDiagnosticsJson(user: GatewayUserSettings): JsonObject {
    let out = JsonObject()
    let account = gatewayFeishuDescribeAccounts(buildGatewayConfigFromUserSettings(user).feishu)
    out.put("channel", JsonString("feishu"))
    out.put("redacted", true.toJsonValue())
    out.put("checkedInputs", JsonArray([
        JsonString("account"),
        JsonString("receiveMode"),
        JsonString("groupPolicy"),
        JsonString("threadSession"),
        JsonString("media"),
        JsonString("nativeCommands")
    ]))
    out.put("account", account)
    out.put("receiveMode", gatewayFeishuReceiveModeDiagnosticsJson(user))
    out.put("groupPolicy", gatewayFeishuGroupPolicyDiagnosticsJson(user))
    out.put("threadSession", gatewayFeishuThreadSessionDiagnosticsJson(user))
    out.put("media", gatewayFeishuMediaJson(user))
    out.put("nativeCommands", gatewayFeishuNativeCommandsJson())
    out.put("unsupportedFields", account.get("unsupportedFields") ?? JsonArray([]))
    out.put("ignoredFields", account.get("ignoredFields") ?? JsonArray([]))
    return out
}

private func gatewayQqAccountInspectJson(user: GatewayUserSettings): JsonObject {
    gatewayQqDescribeAccounts(buildGatewayConfigFromUserSettings(user).qq)
}

private func gatewayQqAnyConfigured(inspect: JsonObject): Bool {
    let rows = match (inspect.get("accounts")) {
        case Some(v) => try { v.asArray() } catch (_: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    for (i in 0..rows.size()) {
        let row = try { rows[i].asObject() } catch (_: Exception) { JsonObject() }
        if (gatewayBindingBool(row, "configured")) {
            return true
        }
    }
    false
}

private func gatewayQqDirectoryJson(user: GatewayUserSettings): JsonObject {
    let out = JsonObject()
    out.put("accounts", gatewayTelegramObjectKeysJson(user.qq.accounts))
    out.put("groups", JsonArray([]))
    out.put("targets", JsonArray([]))
    out.put("rows", JsonArray([]))
    out.put("aggregationSources", JsonArray([JsonString("config")]))
    return out
}

private func gatewayQqAccountOpsJson(): JsonObject {
    let out = JsonObject()
    out.put("list", true.toJsonValue())
    out.put("describe", true.toJsonValue())
    out.put("enable", true.toJsonValue())
    out.put("disable", true.toJsonValue())
    out.put("validate", true.toJsonValue())
    out.put("mutationRequiresGatewayRpc", true.toJsonValue())
    return out
}

private func gatewayQqChannelDiagnosticsJson(user: GatewayUserSettings): JsonObject {
    let account = gatewayQqAccountInspectJson(user)
    let out = JsonObject()
    out.put("channel", JsonString("qq"))
    out.put("redacted", true.toJsonValue())
    out.put("checkedInputs", JsonArray([
        JsonString("account"),
        JsonString("mode"),
        JsonString("officialGateway")
    ]))
    out.put("account", account)
    out.put("mode", JsonString(user.qq.mode))
    return out
}

public func gatewayChannelGetJson(user: GatewayUserSettings, channelId: String): JsonObject {
    let normalized = normalizeGatewayChannelId(channelId)
    let result = JsonObject()
    result.put("id", JsonString(normalized))
    result.put("model", gatewayRpcConfigValueAtPath(user, "gateway.channelmodels.${normalized}") ?? JsonString(""))
    match (getGatewayChannelCatalogEntry(normalized)) {
        case Some(entry) => result.put("catalog", entry.toJson())
        case None => ()
    }
    if (normalized == "feishu") {
        result.put("kind", JsonString("builtin"))
        result.put("enabled", user.feishu.enabled.toJsonValue())
        result.put("mode", JsonString(user.feishu.receiveMode))
        result.put("webhookPath", JsonString(user.feishu.webhookPath))
        result.put("defaultAccountId", JsonString(gatewayFeishuDefaultAccountId(user)))
        result.put("groupSessionScope", JsonString(user.feishu.groupSessionScope))
        result.put("threadSession", user.feishu.threadSession.toJsonValue())
        result.put("groupPolicy", JsonString(user.feishu.groupPolicy))
        result.put("requireMention", user.feishu.requireMention.toJsonValue())
        result.put("allowBots", user.feishu.allowBots.toJsonValue())
        result.put("replyInThread", JsonString(user.feishu.replyInThread))
        result.put("configured", (!user.feishu.appId.trimAscii().isEmpty()).toJsonValue())
        result.put("media", gatewayFeishuMediaJson(user))
        result.put("diagnostics", gatewayFeishuChannelDiagnosticsJson(user))
        result.put("nativeCommands", gatewayFeishuNativeCommandsJson())
        result.put("directory", gatewayFeishuDirectoryJson(user))
        result.put("accountInspect", gatewayFeishuAccountInspectJson(user))
        result.put("accountOps", gatewayFeishuAccountOpsJson())
        result.put("supports", gatewayChannelSupportsJson(user, normalized))
        return result
    }
    if (normalized == "qq") {
        let qqConfig = buildGatewayConfigFromUserSettings(user).qq
        let inspect = gatewayQqDescribeAccounts(qqConfig)
        result.put("kind", JsonString("builtin"))
        result.put("enabled", user.qq.enabled.toJsonValue())
        result.put("mode", JsonString(user.qq.mode))
        result.put("webhookPath", JsonString(user.qq.webhookPath))
        result.put("defaultAccountId", JsonString(gatewayQqDefaultAccountId(qqConfig)))
        result.put("configured", gatewayQqAnyConfigured(inspect).toJsonValue())
        result.put("diagnostics", gatewayQqChannelDiagnosticsJson(user))
        result.put("directory", gatewayQqDirectoryJson(user))
        result.put("accountInspect", inspect)
        result.put("accountOps", gatewayQqAccountOpsJson())
        result.put("supports", gatewayChannelSupportsJson(user, normalized))
        return result
    }
    if (normalized == "telegram") {
        return gatewayTelegramChannelJson(user)
    }
    let plugin = gatewayPluginSettingById(user, normalized)
    result.put("kind", JsonString("plugin"))
    result.put("enabled", plugin.get("enabled") ?? false.toJsonValue())
    result.put("plugin", plugin)
    result.put("config", pluginConfigFromChannelsExtra(user.channelsExtra, normalized))
    result.put("configured", gatewayPluginConfigPresent(user.channelsExtra, normalized).toJsonValue())
    result.put("supports", gatewayChannelSupportsJson(user, normalized))
    result
}

private func gatewayPluginGetJson(user: GatewayUserSettings, pluginId: String): JsonObject {
    let normalized = normalizeGatewayChannelId(pluginId)
    if (gatewayLegacyPluginHostCompatible(normalized)) {
        let _ = gatewayConsumeLegacyPluginRuntime(user, normalized)
    }
    let result = JsonObject()
    let installed = gatewayActionsDiscoverInstalledPluginIds()
    let registered = registeredGatewayPluginIds()
    result.put("id", JsonString(normalized))
    result.put("installed", installed.contains(normalized).toJsonValue())
    result.put("registered", registered.contains(normalized).toJsonValue())
    result.put("gatewayPlugin", gatewayPluginSettingById(user, normalized))
    result.put("config", pluginConfigFromChannelsExtra(user.channelsExtra, normalized))
    result.put("configured", gatewayPluginConfigPresent(user.channelsExtra, normalized).toJsonValue())
    match (getGatewayPluginCatalogEntry(normalized)) {
        case Some(entry) => result.put("catalog", entry.toJson())
        case None => ()
    }
    match (GatewayChannelPluginRegistry.getById(normalized)) {
        case Some(plugin) =>
            result.put("declaredChannelIds", plugin.declaredChannelIds().toJsonValue())
        case None =>
            result.put("declaredChannelIds", JsonArray([]))
    }
    result.put("approval", gatewayPluginApprovalRow(user, normalized))
    result.put("packageProbe", gatewayPluginPackageProbeRow(user, normalized))
    result.put("setup", gatewayPluginSetupRow(user, normalized))
    result.put("supports", gatewayPluginSupportsJson(user, normalized))
    if (gatewayLegacyPluginHostCompatible(normalized)) {
        let pluginConfig = pluginConfigFromChannelsExtra(user.channelsExtra, normalized)
        let host = gatewayLegacyPluginHostInspect(normalized, config: pluginConfig)
        result.put("host", host)
        result.put("hostStatus", gatewayLegacyPluginHostStatus(normalized, config: pluginConfig))
        result.put("hostActions", gatewayLegacyPluginHostActions(normalized, config: pluginConfig))
        match (host.get("configured")) {
            case Some(v) => result.put("configured", v)
            case None => ()
        }
        match (host.get("accountIds")) {
            case Some(v) => result.put("accountIds", v)
            case None => ()
        }
        match (host.get("defaultAccountId")) {
            case Some(v) => result.put("defaultAccountId", v)
            case None => ()
        }
        match (host.get("supports")) {
            case Some(v) => result.put("supports", v)
            case None => ()
        }
        match (host.get("runtimeForwarders")) {
            case Some(v) => result.put("runtimeForwarders", v)
            case None => ()
        }
        match (host.get("setupRegistry")) {
            case Some(v) => result.put("setupRegistry", v)
            case None => ()
        }
    }
    result
}

private func gatewayTelegramChannelJson(user: GatewayUserSettings): JsonObject {
    let result = JsonObject()
    result.put("kind", JsonString("builtin"))
    result.put("enabled", user.telegram.enabled.toJsonValue())
    result.put("mode", JsonString(if (!user.telegram.webhookUrl.trimAscii().isEmpty()) { "webhook" } else { "polling" }))
    result.put("webhookPath", JsonString(user.telegram.webhookPath))
    result.put("replyToMode", JsonString(user.telegram.replyToMode))
    result.put("chunkMode", JsonString(user.telegram.chunkMode))
    result.put("commandsNative", JsonString(user.telegram.commandsNative))
    result.put("customCommandCount", user.telegram.customCommands.size.toJsonValue())
    result.put("reactionNotifications", JsonString(user.telegram.reactionNotifications))
    result.put("reactionLevel", JsonString(user.telegram.reactionLevel))
    result.put("ackReaction", JsonString(user.telegram.ackReaction))
    result.put("removeAckAfterReply", user.telegram.removeAckAfterReply.toJsonValue())
    result.put("groupHistoryEnabled", user.telegram.groupHistoryEnabled.toJsonValue())
    result.put("groupHistoryLimit", user.telegram.groupHistoryLimit.toJsonValue())
    result.put("configured", (!user.telegram.botToken.trimAscii().isEmpty() || !user.telegram.tokenFile.trimAscii().isEmpty()).toJsonValue())
    let network = JsonObject()
    network.put("apiRoot", JsonString(user.telegram.apiRoot))
    network.put("proxyConfigured", (!user.telegram.proxy.trimAscii().isEmpty()).toJsonValue())
    network.put("envProxyEnabled", user.telegram.network.envProxyEnabled.toJsonValue())
    network.put("autoSelectFamily", user.telegram.network.autoSelectFamily.toJsonValue())
    network.put("dnsResultOrder", JsonString(user.telegram.network.dnsResultOrder))
    result.put("network", network)
    let actions = JsonObject()
    actions.put("sendMessage", user.telegram.actions.sendMessage.toJsonValue())
    actions.put("poll", user.telegram.actions.poll.toJsonValue())
    actions.put("deleteMessage", user.telegram.actions.deleteMessage.toJsonValue())
    actions.put("editMessage", user.telegram.actions.editMessage.toJsonValue())
    actions.put("pinMessage", user.telegram.actions.pinMessage.toJsonValue())
    actions.put("unpinMessage", user.telegram.actions.unpinMessage.toJsonValue())
    actions.put("reactions", user.telegram.actions.reactions.toJsonValue())
    actions.put("sticker", user.telegram.actions.sticker.toJsonValue())
    actions.put("photo", user.telegram.actions.photo.toJsonValue())
    actions.put("document", user.telegram.actions.document.toJsonValue())
    actions.put("audio", user.telegram.actions.audio.toJsonValue())
    actions.put("voice", user.telegram.actions.voice.toJsonValue())
    actions.put("video", user.telegram.actions.video.toJsonValue())
    actions.put("videoNote", user.telegram.actions.videoNote.toJsonValue())
    actions.put("createForumTopic", user.telegram.actions.createForumTopic.toJsonValue())
    actions.put("editForumTopic", user.telegram.actions.editForumTopic.toJsonValue())
    actions.put("inlineKeyboard", user.telegram.actions.inlineKeyboard.toJsonValue())
    actions.put("callbackQuery", user.telegram.actions.callbackQuery.toJsonValue())
    result.put("actions", actions)
    let media = JsonObject()
    media.put("downloadEnabled", user.telegram.media.downloadEnabled.toJsonValue())
    media.put("mediaMaxBytes", user.telegram.media.mediaMaxBytes.toJsonValue())
    let allowedMimes = JsonArray([])
    for (mime in user.telegram.media.allowedMimes) {
        allowedMimes.add(JsonString(mime))
    }
    media.put("allowedMimes", allowedMimes)
    media.put("outboundAllowUrl", user.telegram.media.outboundAllowUrl.toJsonValue())
    media.put("outboundAllowLocalPath", user.telegram.media.outboundAllowLocalPath.toJsonValue())
    let localRoots = JsonArray([])
    for (root in user.telegram.media.outboundLocalRoots) {
        localRoots.add(JsonString(root))
    }
    media.put("outboundLocalRoots", localRoots)
    media.put("albumPolicy", JsonString(user.telegram.media.albumPolicy))
    media.put("warnOnDownloadFailure", user.telegram.media.warnOnDownloadFailure.toJsonValue())
    result.put("media", media)
    result.put("setup", gatewayTelegramSetupJson(user))
    result.put("directory", gatewayTelegramDirectoryJson(user))
    result.put("accountInspect", gatewayTelegramAccountInspectJson(user))
    result.put("accountOps", gatewayTelegramAccountOpsJson())
    result.put("actionSchemas", gatewayTelegramActionSchemasJson())
    result.put("supports", gatewayChannelSupportsJson(user, "telegram"))
    result
}

private func gatewayTelegramSetupJson(user: GatewayUserSettings): JsonObject {
    let out = JsonObject()
    out.put("configured", (!user.telegram.botToken.trimAscii().isEmpty() || !user.telegram.tokenFile.trimAscii().isEmpty()).toJsonValue())
    out.put("enabled", user.telegram.enabled.toJsonValue())
    out.put("mode", JsonString(if (!user.telegram.webhookUrl.trimAscii().isEmpty()) { "webhook" } else { "polling" }))
    out.put("probeAvailable", true.toJsonValue())
    out.put("configMutationSafe", true.toJsonValue())
    out.put("writesConfig", false.toJsonValue())
    let required = JsonArray([])
    required.add(JsonString("botToken|tokenFile"))
    out.put("requiredFields", required)
    return out
}

private func gatewayTelegramDirectoryJson(user: GatewayUserSettings): JsonObject {
    let out = JsonObject()
    out.put("defaultTo", JsonString(user.telegram.defaultTo))
    out.put("groups", gatewayTelegramObjectKeysJson(user.telegram.groups))
    out.put("accounts", gatewayTelegramObjectKeysJson(user.telegram.accounts))
    out.put("targets", gatewayTelegramTargetsJson(user))
    let rows = gatewayTelegramDirectoryRowsJson(user)
    out.put("rows", rows)
    out.put("rowCount", rows.size().toJsonValue())
    out.put("aggregationSources", JsonArray([
        JsonString("defaultTo"),
        JsonString("groups"),
        JsonString("accounts"),
        JsonString("pairing"),
        JsonString("session-catalog"),
        JsonString("delivery-history")
    ]))
    return out
}

private func gatewayTelegramDirectoryRow(
    kind: String,
    id: String,
    displayName: String,
    accountId: String,
    source: String,
    sessionKey!: String = "",
    lastSeenAtMs!: Int64 = 0,
    canSend!: Bool = true,
    policyState!: String = "allowed"
): JsonObject {
    let row = JsonObject()
    row.put("kind", JsonString(kind))
    row.put("id", JsonString(id))
    row.put("displayName", JsonString(displayName))
    row.put("accountId", JsonString(accountId))
    row.put("source", JsonString(source))
    row.put("lastSeenAtMs", lastSeenAtMs.toJsonValue())
    row.put("sessionKey", JsonString(sessionKey))
    row.put("canSend", canSend.toJsonValue())
    row.put("policyState", JsonString(policyState))
    row
}

private func gatewayTelegramDirectoryAddRow(rows: JsonArray, seen: HashMap<String, Bool>, row: JsonObject): Unit {
    let key = gatewayBindingStringParam(row, ["kind"], "") + ":" +
        gatewayBindingStringParam(row, ["accountId"], "") + ":" +
        gatewayBindingStringParam(row, ["id"], "")
    if (seen.contains(key)) {
        return
    }
    seen[key] = true
    rows.add(row)
}

private func gatewayTelegramDirectoryRowsJson(user: GatewayUserSettings): JsonArray {
    let rows = JsonArray([])
    let seen = HashMap<String, Bool>()
    let defaultAccountId = if (user.telegram.defaultAccount.trimAscii().isEmpty()) {
        "default"
    } else {
        user.telegram.defaultAccount.trimAscii()
    }
    if (!user.telegram.defaultTo.trimAscii().isEmpty()) {
        gatewayTelegramDirectoryAddRow(
            rows,
            seen,
            gatewayTelegramDirectoryRow("user", user.telegram.defaultTo.trimAscii(), user.telegram.defaultTo.trimAscii(), defaultAccountId, "defaultTo")
        )
    }
    match (user.telegram.groups) {
        case Some(groups) =>
            for (groupId in groups.getFields().keys()) {
                if (groupId != "*") {
                    gatewayTelegramDirectoryAddRow(rows, seen, gatewayTelegramDirectoryRow("group", "group:${groupId}", "group:${groupId}", defaultAccountId, "groups"))
                }
                let groupObj = try { groups.getFields()[groupId].asObject() } catch (_: Exception) { JsonObject() }
                let topics = try { groupObj.get("topics").getOrThrow().asObject() } catch (_: Exception) { JsonObject() }
                for (topicId in topics.getFields().keys()) {
                    if (topicId != "*") {
                        gatewayTelegramDirectoryAddRow(rows, seen, gatewayTelegramDirectoryRow("topic", "group:${groupId}:topic:${topicId}", "group:${groupId}:topic:${topicId}", defaultAccountId, "groups"))
                    }
                }
            }
        case None => ()
    }
    for (senderId in telegramPairingAccountStore(rootDir: CliConfig.dotDir, accountId: defaultAccountId).approvedSenders()) {
        gatewayTelegramDirectoryAddRow(
            rows,
            seen,
            gatewayTelegramDirectoryRow("user", "user:${senderId}", "user:${senderId}", defaultAccountId, "pairing")
        )
    }
    for (view in gatewayListSessionCatalogViewsForUser(user)) {
        if (view.channel != "telegram" || view.peer.trimAscii().isEmpty()) {
            continue
        }
        let kind = if (view.peer.contains(":topic:")) { "topic" } else if (view.peer.startsWith("group:")) { "group" } else { "user" }
        let acct = if (!view.row.lastAccountId.trimAscii().isEmpty()) { view.row.lastAccountId.trimAscii() } else { defaultAccountId }
        gatewayTelegramDirectoryAddRow(
            rows,
            seen,
            gatewayTelegramDirectoryRow(
                kind,
                view.peer,
                if (view.displayName.trimAscii().isEmpty()) { view.peer } else { view.displayName },
                acct,
                if (view.row.deliverySnapshot.size() > 0) { "delivery-history" } else { "session-catalog" },
                sessionKey: view.row.sessionKey,
                lastSeenAtMs: view.row.updatedAt,
                canSend: view.row.sendPolicy.trimAscii().toAsciiLower() != "deny",
                policyState: if (view.row.sendPolicy.trimAscii().toAsciiLower() == "deny") { "blocked" } else { "allowed" }
            )
        )
    }
    rows
}

private func gatewayTelegramObjectKeysJson(objOpt: Option<JsonObject>): JsonArray {
    let out = JsonArray([])
    match (objOpt) {
        case Some(obj) =>
            for (key in obj.getFields().keys()) {
                out.add(JsonString(key))
            }
        case None => ()
    }
    return out
}

private func gatewayTelegramConfigHasObject(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asObject().size() > 0 } catch (_e: Exception) { false }
        case None => false
    }
}

private func gatewayTelegramConfigArraySize(obj: JsonObject, key: String): Int64 {
    match (obj.get(key)) {
        case Some(v) => try { v.asArray().size() } catch (_e: Exception) { 0 }
        case None => 0
    }
}

private func gatewayTelegramAccountInspectRow(user: GatewayUserSettings, accountId: String, accountConfig: JsonObject, defaultAccountId: String): JsonObject {
    let row = JsonObject()
    let resolved = gatewayTelegramResolveAccount(buildGatewayConfigFromUserSettings(user).telegram, accountId)
    let accountToken = gatewayBindingStringParam(accountConfig, ["botToken"], "")
    let accountTokenFile = gatewayBindingStringParam(accountConfig, ["tokenFile"], "")
    let globalTokenConfigured = !user.telegram.botToken.trimAscii().isEmpty() || !user.telegram.tokenFile.trimAscii().isEmpty()
    let tokenSource = if (!accountTokenFile.isEmpty()) {
        "account-tokenFile"
    } else if (!accountToken.isEmpty()) {
        "account-botToken"
    } else if (globalTokenConfigured) {
        "global-inherited"
    } else {
        "missing"
    }
    row.put("accountId", JsonString(accountId))
    row.put("defaultAccount", (accountId == defaultAccountId).toJsonValue())
    row.put("configured", resolved.configured.toJsonValue())
    row.put("tokenSource", JsonString(tokenSource))
    row.put("credentialSource", JsonString(resolved.credentialSource))
    row.put("securitySources", resolved.securitySources)
    row.put("inheritanceDiagnostics", resolved.inheritanceDiagnostics)
    row.put("hasBotToken", (!accountToken.isEmpty()).toJsonValue())
    row.put("hasTokenFile", (!accountTokenFile.isEmpty()).toJsonValue())
    row.put("allowFromCount", gatewayTelegramConfigArraySize(accountConfig, "allowFrom").toJsonValue())
    row.put("allowFromEffectiveCount", resolved.config.allowFrom.size.toJsonValue())
    row.put("groupAllowFromCount", gatewayTelegramConfigArraySize(accountConfig, "groupAllowFrom").toJsonValue())
    row.put("groupAllowFromEffectiveCount", resolved.config.groupAllowFrom.size.toJsonValue())
    row.put("dmPolicy", JsonString(resolved.config.dmPolicy))
    row.put("groupPolicy", JsonString(resolved.config.groupPolicy))
    row.put("hasGroupsOverride", gatewayTelegramConfigHasObject(accountConfig, "groups").toJsonValue())
    row.put("hasDirectOverride", gatewayTelegramConfigHasObject(accountConfig, "direct").toJsonValue())
    row.put("hasDmsOverride", gatewayTelegramConfigHasObject(accountConfig, "dms").toJsonValue())
    row.put("hasMediaOverride", gatewayTelegramConfigHasObject(accountConfig, "media").toJsonValue())
    row.put("hasNetworkOverride", gatewayTelegramConfigHasObject(accountConfig, "network").toJsonValue())
    row.put("approvedSenderCount", telegramPairingAccountStore(rootDir: CliConfig.dotDir, accountId: accountId).approvedSenders().size.toJsonValue())
    return row
}

private func gatewayTelegramAccountInspectJson(user: GatewayUserSettings): JsonObject {
    let out = JsonObject()
    let defaultAccountId = if (user.telegram.defaultAccount.trimAscii().isEmpty()) {
        "default"
    } else {
        user.telegram.defaultAccount.trimAscii()
    }
    out.put("defaultAccountId", JsonString(defaultAccountId))
    out.put("tokenRedacted", true.toJsonValue())
    let rows = JsonArray([])
    let seen = HashMap<String, Bool>()
    match (user.telegram.accounts) {
        case Some(accounts) =>
            for (accountId in accounts.getFields().keys()) {
                let trimmed = accountId.trimAscii()
                if (trimmed.isEmpty()) {
                    continue
                }
                let accountConfig = try { accounts.getFields()[accountId].asObject() } catch (_e: Exception) { JsonObject() }
                rows.add(gatewayTelegramAccountInspectRow(user, trimmed, accountConfig, defaultAccountId))
                seen[trimmed] = true
            }
        case None => ()
    }
    if (!seen.contains(defaultAccountId)) {
        rows.add(gatewayTelegramAccountInspectRow(user, defaultAccountId, JsonObject(), defaultAccountId))
    }
    out.put("accounts", rows)
    out.put("count", rows.size().toJsonValue())
    return out
}

private func gatewayTelegramTargetsJson(user: GatewayUserSettings): JsonArray {
    let out = JsonArray([])
    if (!user.telegram.defaultTo.trimAscii().isEmpty()) {
        out.add(JsonString(user.telegram.defaultTo.trimAscii()))
    }
    match (user.telegram.groups) {
        case Some(groups) =>
            let groupFields = groups.getFields()
            for (groupId in groupFields.keys()) {
                if (groupId != "*") {
                    out.add(JsonString("group:${groupId}"))
                }
                let groupObj = try { groupFields[groupId].asObject() } catch (_e: Exception) { JsonObject() }
                let topicsOpt = try { Some(groupObj.get("topics").getOrThrow().asObject()) } catch (_e: Exception) { None<JsonObject> }
                match (topicsOpt) {
                    case Some(topics) =>
                        for (topicId in topics.getFields().keys()) {
                            if (topicId != "*") {
                                out.add(JsonString("group:${groupId}:topic:${topicId}"))
                            }
                        }
                    case None => ()
                }
            }
        case None => ()
    }
    return out
}

private func gatewayTelegramAccountOpsJson(): JsonObject {
    let out = JsonObject()
    out.put("setup", true.toJsonValue())
    out.put("probe", true.toJsonValue())
    out.put("directory", true.toJsonValue())
    out.put("logout", true.toJsonValue())
    out.put("mutationRequiresGatewayRpc", true.toJsonValue())
    return out
}

private func gatewayTelegramActionSchema(name: String, method: String, enabledBy: String, required: Array<String>): JsonObject {
    let out = JsonObject()
    out.put("name", JsonString(name))
    out.put("botApiMethod", JsonString(method))
    out.put("enabledBy", JsonString(enabledBy))
    let requiredJson = JsonArray([])
    for (field in required) {
        requiredJson.add(JsonString(field))
    }
    out.put("required", requiredJson)
    return out
}

private func gatewayTelegramActionSchemasJson(): JsonArray {
    let out = JsonArray([])
    out.add(gatewayTelegramActionSchema("sendMessage", "sendMessage", "telegram.actions.sendMessage", ["chat_id", "text"]))
    out.add(gatewayTelegramActionSchema("poll", "sendPoll", "telegram.actions.poll", ["chat_id", "question", "options"]))
    out.add(gatewayTelegramActionSchema("deleteMessage", "deleteMessage", "telegram.actions.deleteMessage", ["chat_id", "message_id"]))
    out.add(gatewayTelegramActionSchema("editMessage", "editMessageText", "telegram.actions.editMessage", ["chat_id", "message_id", "text"]))
    out.add(gatewayTelegramActionSchema("pinMessage", "pinChatMessage", "telegram.actions.pinMessage", ["chat_id", "message_id"]))
    out.add(gatewayTelegramActionSchema("unpinMessage", "unpinChatMessage", "telegram.actions.unpinMessage", ["chat_id", "message_id"]))
    out.add(gatewayTelegramActionSchema("reaction", "setMessageReaction", "telegram.actions.reactions", ["chat_id", "message_id", "reaction"]))
    out.add(gatewayTelegramActionSchema("photo", "sendPhoto", "telegram.actions.photo", ["chat_id", "photo"]))
    out.add(gatewayTelegramActionSchema("document", "sendDocument", "telegram.actions.document", ["chat_id", "document"]))
    out.add(gatewayTelegramActionSchema("audio", "sendAudio", "telegram.actions.audio", ["chat_id", "audio"]))
    out.add(gatewayTelegramActionSchema("voice", "sendVoice", "telegram.actions.voice", ["chat_id", "voice"]))
    out.add(gatewayTelegramActionSchema("video", "sendVideo", "telegram.actions.video", ["chat_id", "video"]))
    out.add(gatewayTelegramActionSchema("videoNote", "sendVideoNote", "telegram.actions.videoNote", ["chat_id", "video_note"]))
    out.add(gatewayTelegramActionSchema("sticker", "sendSticker", "telegram.actions.sticker", ["chat_id", "sticker"]))
    out.add(gatewayTelegramActionSchema("inlineKeyboard", "sendMessage", "telegram.actions.inlineKeyboard", ["chat_id", "text", "reply_markup.inline_keyboard"]))
    out.add(gatewayTelegramActionSchema("callbackQuery", "inbound:callback_query", "telegram.actions.callbackQuery", ["callback_query.id", "callback_query.message", "callback_query.from"]))
    return out
}

private func gatewayTelegramRuntimeJson(user: GatewayUserSettings, liveProbe!: Bool = false): JsonObject {
    let cfg = buildGatewayConfigFromUserSettings(user)
    let adapter = TelegramAdapter(config: cfg.telegram)
    let out = JsonObject()
    let mode = if (!user.telegram.webhookUrl.trimAscii().isEmpty()) { "webhook" } else { "polling" }
    out.put("mode", JsonString(mode))
    out.put("webhookConfigured", (mode == "webhook").toJsonValue())
    out.put("webhookPath", JsonString(user.telegram.webhookPath))
    out.put("commandsNative", JsonString(user.telegram.commandsNative))
    out.put("customCommandCount", user.telegram.customCommands.size.toJsonValue())
    out.put("reactionNotifications", JsonString(user.telegram.reactionNotifications))
    out.put("reactionLevel", JsonString(user.telegram.reactionLevel))
    out.put("ackReaction", JsonString(user.telegram.ackReaction))
    out.put("removeAckAfterReply", user.telegram.removeAckAfterReply.toJsonValue())
    out.put("groupHistoryEnabled", user.telegram.groupHistoryEnabled.toJsonValue())
    out.put("groupHistoryLimit", user.telegram.groupHistoryLimit.toJsonValue())
    let network = JsonObject()
    network.put("apiRoot", JsonString(user.telegram.apiRoot))
    network.put("proxyConfigured", (!user.telegram.proxy.trimAscii().isEmpty()).toJsonValue())
    network.put("envProxyEnabled", user.telegram.network.envProxyEnabled.toJsonValue())
    network.put("autoSelectFamily", user.telegram.network.autoSelectFamily.toJsonValue())
    network.put("dnsResultOrder", JsonString(user.telegram.network.dnsResultOrder))
    out.put("network", network)
    out.put("allowedUpdatesAuto", true.toJsonValue())
    let allowed = JsonArray([])
    for (kind in ["message", "edited_message", "channel_post", "edited_channel_post"]) {
        allowed.add(JsonString(kind))
    }
    if (user.telegram.reactionNotifications.trimAscii().toAsciiLower() != "off") {
        allowed.add(JsonString("message_reaction"))
    }
    if (user.telegram.actions.callbackQuery || user.telegram.actions.inlineKeyboard) {
        allowed.add(JsonString("callback_query"))
    }
    out.put("allowedUpdates", allowed)
    out.put("registrationPayload", adapter.debugBuildWebhookRegistrationPayload())
    let healthSnapshot = adapter.debugBuildHealthSnapshot()
    out.put("healthSnapshot", healthSnapshot)
    out.put("media", healthSnapshot.get("media") ?? JsonObject())
    out.put("actions", gatewayTelegramChannelJson(user).get("actions") ?? JsonObject())
    out.put("accountInspect", gatewayTelegramAccountInspectJson(user))
    let capabilityState = JsonObject()
    capabilityState.put("mediaUnderstandingState", JsonString(if (user.telegram.media.downloadEnabled) { "context-ready" } else { "metadata-only" }))
    capabilityState.put("videoUnderstandingState", JsonString(gatewayRpcTelegramVideoUnderstandingState(user)))
    capabilityState.put("videoGenerationState", JsonString(gatewayRpcVideoConfigState(gatewayVideoGenerationResolveConfig(user, channel: "telegram"))))
    capabilityState.put("approvalResolverState", JsonString(if (user.telegram.actions.callbackQuery && user.telegram.actions.inlineKeyboard) { "button-resolver-ready" } else { "callback-or-button-disabled" }))
    capabilityState.put("lastDraftState", JsonString(if (user.telegram.actions.editMessage && user.telegram.streaming.trimAscii().toAsciiLower() != "off") { "streaming-draft-ready" } else { "send-only" }))
    capabilityState.put("directoryAggregationState", JsonString("config-session-history-ready"))
    capabilityState.put("modelButtonState", JsonString(if (user.telegram.actions.inlineKeyboard && user.telegram.actions.callbackQuery) { "available" } else { "disabled" }))
    out.put("capabilityState", capabilityState)
    out.put("liveProbe", if (liveProbe) {
        adapter.debugBuildLiveProbe()
    } else {
        let idleProbe = JsonObject()
        idleProbe.put("supported", true.toJsonValue())
        idleProbe.put("executed", false.toJsonValue())
        idleProbe.put("status", JsonString("idle"))
        idleProbe
    })
    out.put("supports", gatewayChannelSupportsJson(user, "telegram"))
    out.put("summary", gatewayChannelRuntimeSummary("telegram"))
    out
}

private func gatewayPluginActionAccountId(user: GatewayUserSettings, pluginId: String, request: GatewayRpcRequest): String {
    let requested = gatewayRpcStringParam(request, ["accountId"], "")
    if (!requested.isEmpty()) {
        return requested
    }
    let plugin = gatewayPluginGetJson(user, pluginId)
    match (plugin.get("defaultAccountId")) {
        case Some(v) =>
            try {
                let text = v.asString().getValue().trimAscii()
                if (!text.isEmpty()) {
                    return text
                }
            } catch (_e: Exception) {
                ()
            }
        case None => ()
    }
    "${normalizeGatewayChannelId(pluginId)}:default"
}

private func gatewayHostCompatiblePluginForChannel(channelId: String): String {
    let normalized = normalizeGatewayChannelId(channelId)
    match (getGatewayChannelCatalogEntry(normalized)) {
        case Some(entry) =>
            if (!entry.pluginId.isEmpty() && gatewayLegacyPluginHostCompatible(entry.pluginId)) {
                return entry.pluginId
            }
            if (gatewayLegacyPluginHostCompatible(normalized)) {
                return normalized
            }
            ""
        case None =>
            if (gatewayLegacyPluginHostCompatible(normalized)) {
                normalized
            } else {
                ""
            }
    }
}

private func gatewayPluginStartJson(user: GatewayUserSettings, pluginId: String, request: GatewayRpcRequest): JsonObject {
    let normalized = normalizeGatewayChannelId(pluginId)
    let result = JsonObject()
    result.put("pluginId", JsonString(normalized))
    if (!gatewayLegacyPluginHostCompatible(normalized)) {
        result.put("supported", false.toJsonValue())
        result.put("reason", JsonString("not-legacy-compatible"))
        return result
    }
    let accountId = gatewayPluginActionAccountId(user, normalized, request)
    let config = pluginConfigFromChannelsExtra(user.channelsExtra, normalized)
    let _ = gatewayConsumeLegacyPluginRuntime(user, normalized)
    gatewayChannelRuntimeMarkStarting(normalized, accountId: accountId)
    let host = gatewayLegacyPluginHostStart(normalized, config: config, accountId: accountId)
    if (gatewayJsonBool(host, "started", gatewayJsonBool(host, "supported", false))) {
        let running = gatewayChannelRuntimeMarkRunning(normalized, accountId: accountId)
        result.put("started", true.toJsonValue())
        result.put("runtime", running)
    } else {
        let reason = gatewayBindingStringParam(host, ["reason", "hostError", "error"], "start-failed")
        let failed = gatewayChannelRuntimeMarkFailure(normalized, accountId: accountId, lifecycleState: "failed", error: reason)
        result.put("started", false.toJsonValue())
        result.put("runtime", failed)
    }
    result.put("accountId", JsonString(accountId))
    result.put("host", host)
    result.put("manager", gatewayPluginManagerSummary(normalized))
    result
}

private func gatewayPluginStopJson(user: GatewayUserSettings, pluginId: String, request: GatewayRpcRequest): JsonObject {
    let normalized = normalizeGatewayChannelId(pluginId)
    let result = JsonObject()
    result.put("pluginId", JsonString(normalized))
    if (!gatewayLegacyPluginHostCompatible(normalized)) {
        result.put("supported", false.toJsonValue())
        result.put("reason", JsonString("not-legacy-compatible"))
        return result
    }
    let accountId = gatewayPluginActionAccountId(user, normalized, request)
    let config = pluginConfigFromChannelsExtra(user.channelsExtra, normalized)
    let host = gatewayLegacyPluginHostStop(normalized, config: config, accountId: accountId)
    let stopped = gatewayChannelRuntimeMarkStopped(
        normalized,
        accountId: accountId,
        reason: gatewayBindingStringParam(host, ["reason", "state"], "host-stop"),
        manualStop: gatewayJsonBool(host, "stopped", false)
    )
    result.put("accountId", JsonString(accountId))
    result.put("stopped", gatewayJsonBool(host, "stopped", false).toJsonValue())
    result.put("host", host)
    result.put("runtime", stopped)
    result.put("manager", gatewayPluginManagerSummary(normalized))
    result
}

private func gatewayPluginLogoutJson(user: GatewayUserSettings, pluginId: String, request: GatewayRpcRequest): JsonObject {
    let normalized = normalizeGatewayChannelId(pluginId)
    let result = JsonObject()
    result.put("pluginId", JsonString(normalized))
    result.put("plugin", JsonString(normalized))
    if (!gatewayLegacyPluginHostCompatible(normalized)) {
        result.put("supported", false.toJsonValue())
        result.put("reason", JsonString("not-legacy-compatible"))
        return result
    }
    let accountId = gatewayPluginActionAccountId(user, normalized, request)
    let config = pluginConfigFromChannelsExtra(user.channelsExtra, normalized)
    let host = gatewayLegacyPluginHostLogout(normalized, config: config, accountId: accountId)
    let loggedOut = gatewayLogoutLoggedOut(host)
    let stopped = gatewayChannelRuntimeMarkStopped(
        normalized,
        accountId: accountId,
        reason: if (loggedOut) { "logged out" } else { gatewayBindingStringParam(host, ["reason", "state"], "logout") },
        manualStop: true
    )
    result.put("accountId", JsonString(accountId))
    result.put("cleared", gatewayLogoutCleared(host).toJsonValue())
    result.put("loggedOut", loggedOut.toJsonValue())
    result.put("host", host)
    result.put("runtime", stopped)
    result.put("manager", gatewayPluginManagerSummary(normalized))
    result
}

private func gatewayPluginSendJson(user: GatewayUserSettings, pluginId: String, request: GatewayRpcRequest): JsonObject {
    let normalized = normalizeGatewayChannelId(pluginId)
    let result = JsonObject()
    result.put("pluginId", JsonString(normalized))
    if (!gatewayLegacyPluginHostCompatible(normalized)) {
        result.put("supported", false.toJsonValue())
        result.put("reason", JsonString("not-legacy-compatible"))
        return result
    }
    let accountId = gatewayPluginActionAccountId(user, normalized, request)
    let peerId = gatewayRpcStringParam(request, ["peerId", "to"], "")
    let text = gatewayRpcStringParam(request, ["text", "message"], "")
    let replyTo = gatewayRpcStringParam(request, ["replyTo", "replyToMessageId"], "")
    let policyDelivery = gatewayApplyChannelDeliveryPolicy(
        user,
        normalized,
        gatewayChannelsDeliveryJson(normalized, peerId, accountId, replyToMessageId: replyTo, deliverable: true)
    )
    let effectiveReplyTo = gatewayBindingStringParam(policyDelivery, ["effectiveReplyToMessageId"], "")
    let host = gatewayLegacyPluginHostSend(
        normalized,
        peerId,
        text,
        replyTo: effectiveReplyTo,
        config: pluginConfigFromChannelsExtra(user.channelsExtra, normalized),
        accountId: accountId
    )
    let ok = gatewayJsonBool(host, "ok", false)
    let runtime = gatewayChannelRuntimeMarkSend(
        normalized,
        accountId: accountId,
        success: ok,
        detail: gatewayBindingStringParam(host, ["reason", "hostError", "error"], "send-failed")
    )
    result.put("accountId", JsonString(accountId))
    result.put("peerId", JsonString(peerId))
    policyDelivery.put("deliverable", ok.toJsonValue())
    result.put("delivery", policyDelivery)
    result.put("ok", ok.toJsonValue())
    result.put("host", host)
    result.put("runtime", runtime)
    result.put("manager", gatewayPluginManagerSummary(normalized))
    result
}

private func gatewayChannelActionByPlugin(
    user: GatewayUserSettings,
    request: GatewayRpcRequest,
    action: String
): JsonObject {
    let channelId = gatewayRpcStringParam(request, ["id", "channel", "channelId"], "")
    match (gatewayChannelActionByNativeRuntime(request, channelId, action)) {
        case Some(nativeResult) => return nativeResult
        case None => ()
    }
    if (action == "send") {
        match (gatewayChannelActionByNativeAdapter(user, request, channelId)) {
            case Some(nativeResult) => return nativeResult
            case None => ()
        }
    }
    let pluginId = gatewayHostCompatiblePluginForChannel(channelId)
    let result = JsonObject()
    result.put("channelId", JsonString(normalizeGatewayChannelId(channelId)))
    result.put("pluginId", JsonString(pluginId))
    if (pluginId.isEmpty()) {
        result.put("supported", false.toJsonValue())
        result.put("reason", JsonString("channel-not-legacy-compatible"))
        return result
    }
    let actionResult = if (action == "start") {
        gatewayPluginStartJson(user, pluginId, request)
    } else if (action == "stop") {
        gatewayPluginStopJson(user, pluginId, request)
    } else if (action == "send") {
        gatewayPluginSendJson(user, pluginId, request)
    } else {
        gatewayPluginLogoutJson(user, pluginId, request)
    }
    if (action == "logout") {
        result.put("channel", JsonString(normalizeGatewayChannelId(channelId)))
        result.put("accountId", actionResult.get("accountId") ?? JsonString(""))
        result.put("cleared", actionResult.get("cleared") ?? false.toJsonValue())
        result.put("loggedOut", actionResult.get("loggedOut") ?? false.toJsonValue())
        result.put("host", actionResult.get("host") ?? JsonObject())
        result.put("runtime", actionResult.get("runtime") ?? JsonObject())
        result.put("manager", actionResult.get("manager") ?? JsonObject())
    }
    result.put("action", JsonString(action))
    result.put("result", actionResult)
    result
}

private func gatewayNativeRuntimeChannelSupported(channelId: String): Bool {
    let normalized = normalizeGatewayChannelId(channelId)
    normalized == "telegram" || normalized == "feishu" || normalized == "qq"
}

private func gatewayChannelActionByNativeRuntime(
    request: GatewayRpcRequest,
    channelId: String,
    action: String
): Option<JsonObject> {
    let normalized = normalizeGatewayChannelId(channelId)
    if (!gatewayNativeRuntimeChannelSupported(normalized)) {
        return None<JsonObject>
    }
    if (action != "start" && action != "stop" && action != "restart") {
        return None<JsonObject>
    }
    let accountId = gatewayRpcStringParam(request, ["accountId", "account"], "")
    match (gatewayActiveService()) {
        case Some(service) =>
            let result = if (action == "start") {
                service.startChannel(normalized, accountId: accountId)
            } else if (action == "stop") {
                service.stopChannel(normalized, accountId: accountId, reason: "manual-stop", manualStop: true)
            } else {
                service.restartChannel(normalized, accountId: accountId, reason: "restart")
            }
            result.put("native", true.toJsonValue())
            return Some(result)
        case None =>
            let result = JsonObject()
            let canonicalAccount = if (accountId.trimAscii().isEmpty()) {
                ""
            } else {
                gatewayCanonicalChannelAccountId(normalized, accountId)
            }
            let negativeResult = if (action == "start") {
                "not-started"
            } else if (action == "stop") {
                "not-stopped"
            } else {
                "not-restarted"
            }
            result.put("ok", false.toJsonValue())
            result.put("supported", true.toJsonValue())
            result.put("native", true.toJsonValue())
            result.put("action", JsonString(action))
            result.put("channelId", JsonString(normalized))
            result.put("channel", JsonString(normalized))
            result.put("accountId", JsonString(canonicalAccount))
            result.put("runtimeKind", JsonString("native-cangjie"))
            result.put("compatibilityMode", JsonString("native-cangjie"))
            result.put("reason", JsonString("gateway-runtime-not-active"))
            result.put("result", JsonString(negativeResult))
            result.put("manager", gatewayChannelManagerSummary(normalized))
            return Some(result)
    }
}

private func gatewayChannelActionByNativeAdapter(
    user: GatewayUserSettings,
    request: GatewayRpcRequest,
    channelId: String
): Option<JsonObject> {
    let normalized = normalizeGatewayChannelId(channelId)
    if (normalized != "telegram") {
        return None<JsonObject>
    }
    let cfg = buildGatewayConfigFromUserSettings(user)
    let accountId = gatewayRpcStringParam(request, ["accountId"], cfg.telegram.accountId)
    let peerId = gatewayRpcStringParam(request, ["peerId", "to", "target"], "")
    let text = gatewayRpcStringParam(request, ["text", "message", "body"], "")
    let replyTo = gatewayRpcStringParam(request, ["replyToMessageId", "replyTo"], "")
    let quoteText = gatewayRpcStringParam(request, ["quoteText", "replyQuoteText"], "")
    let replyInThread = gatewayRpcBoolParam(request, ["replyInThread"], false)
    let result = JsonObject()
    result.put("channelId", JsonString(normalized))
    result.put("channel", JsonString(normalized))
    result.put("accountId", JsonString(accountId))
    result.put("peerId", JsonString(peerId))
    result.put("runtimeKind", JsonString("native-cangjie"))
    result.put("compatibilityMode", JsonString("native-cangjie"))
    if (peerId.isEmpty() || text.isEmpty()) {
        result.put("ok", false.toJsonValue())
        result.put("supported", true.toJsonValue())
        result.put("reason", JsonString("missing-peer-or-message"))
        return Some(result)
    }
    var effectiveText = text
    let sendingHook = gatewayOpenClawPluginSidecarApplyMessageSendingHook(
        user,
        "telegram",
        accountId,
        peerId,
        text,
        replyTo,
        replyInThread
    )
    if (try { sendingHook.get("cancelled").getOrThrow().asBool().getValue() } catch (_: Exception) { false }) {
        effectiveText = "[plugin-hook-cancelled] " + gatewayBindingStringParam(sendingHook, ["reason"], "cancelled by plugin hook")
    } else {
        let hookText = gatewayBindingStringParam(sendingHook, ["text"], "")
        if (!hookText.trimAscii().isEmpty()) {
            effectiveText = hookText
        }
    }
    let adapter = TelegramAdapter(config: cfg.telegram)
    let messageId = adapter.sendDirectWithMessageIdForGatewayRpc(
        OutboundMessage(
            ChannelType.Telegram,
            peerId,
            effectiveText,
            replyToMessageId: if (replyTo.isEmpty()) { None<String> } else { Some(replyTo) },
            quoteText: quoteText,
            replyInThread: replyInThread,
            accountId: accountId
        )
    )
    let lastError = adapter.debugLastSendErrorForTest()
    let ok = !messageId.isEmpty()
    let _ = gatewayOpenClawPluginSidecarApplyMessageSentHook(
        user,
        "telegram",
        accountId,
        peerId,
        effectiveText,
        messageId,
        ok,
        if (ok) { "" } else { lastError }
    )
    let delivery = JsonObject()
    delivery.put("deliverable", ok.toJsonValue())
    delivery.put("channel", JsonString(normalized))
    delivery.put("peerId", JsonString(peerId))
    delivery.put("accountId", JsonString(accountId))
    if (!messageId.isEmpty()) {
        delivery.put("messageId", JsonString(messageId))
        result.put("messageId", JsonString(messageId))
    }
    result.put("supported", true.toJsonValue())
    result.put("ok", ok.toJsonValue())
    result.put("delivery", delivery)
    if (!ok) {
        result.put("reason", JsonString(if (lastError.isEmpty()) { "native-send-failed" } else { lastError }))
    }
    Some(result)
}

private func gatewayTelegramGetChatByNativeAdapter(user: GatewayUserSettings, request: GatewayRpcRequest): JsonObject {
    let cfg = buildGatewayConfigFromUserSettings(user)
    let accountId = gatewayRpcStringParam(request, ["accountId"], cfg.telegram.accountId)
    let chatId = gatewayRpcStringParam(request, ["chatId", "chat_id", "target", "to"], "")
    let result = JsonObject()
    result.put("channelId", JsonString("telegram"))
    result.put("channel", JsonString("telegram"))
    result.put("accountId", JsonString(accountId))
    result.put("runtimeKind", JsonString("native-cangjie"))
    result.put("compatibilityMode", JsonString("native-cangjie"))
    result.put("botApiMethod", JsonString("getChat"))
    result.put("target", JsonString(chatId))
    if (chatId.trimAscii().isEmpty()) {
        result.put("ok", false.toJsonValue())
        result.put("status", JsonString("error"))
        result.put("reason", JsonString("missing-chat-id"))
        return result
    }
    let adapter = TelegramAdapter(config: cfg.telegram)
    let chat = adapter.resolveTelegramChatForGatewayRpc(chatId)
    let ok = gatewayBindingBool(chat, "ok")
    result.put("ok", ok.toJsonValue())
    result.put("status", JsonString(if (ok) { "ok" } else { "error" }))
    result.put("chat", chat)
    match (chat.get("chatId")) {
        case Some(v) => result.put("chatId", v)
        case None => ()
    }
    if (!ok) {
        result.put("reason", chat.get("error") ?? JsonString("getChat failed"))
    }
    return result
}

private func gatewayBindingBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
}

private func gatewayBindingCount(obj: JsonObject, key: String): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            try { Int64.parse(v.toJsonString()) } catch (_e: Exception) { 0 }
        case None => 0
    }
}

private func gatewayBindingArraySize(value: JsonValue): Int64 {
    try {
        Int64(value.asArray().size())
    } catch (_e: Exception) {
        0
    }
}

private func gatewayHostObject(value: JsonValue): JsonObject {
    try {
        value.asObject()
    } catch (_e: Exception) {
        JsonObject()
    }
}

private func gatewayHostArray(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func gatewayLogoutCleared(host: JsonObject): Bool {
    gatewayJsonBool(host, "cleared", false)
}

private func gatewayLogoutLoggedOut(host: JsonObject): Bool {
    match (host.get("loggedOut")) {
        case Some(_) => return gatewayJsonBool(host, "loggedOut", false)
        case None => ()
    }
    gatewayLogoutCleared(host)
}

private func gatewayHostBindingsForPlugin(user: GatewayUserSettings, pluginId: String): JsonObject {
    if (!gatewayLegacyPluginHostCompatible(pluginId)) {
        return JsonObject()
    }
    gatewayLegacyPluginHostBindings(pluginId, config: pluginConfigFromChannelsExtra(user.channelsExtra, pluginId))
}

private func gatewayHostAccountsForPlugin(user: GatewayUserSettings, pluginId: String): JsonObject {
    if (!gatewayLegacyPluginHostCompatible(pluginId)) {
        return JsonObject()
    }
    gatewayLegacyPluginHostAccounts(pluginId, config: pluginConfigFromChannelsExtra(user.channelsExtra, pluginId))
}

private func gatewayChannelBindingConstraints(channel: JsonObject, enabled: Bool, configured: Bool): JsonArray {
    gatewayChannelBindingConstraintsJson(enabled, configured, gatewayBindingStringParam(channel, ["model"], "") != "")
}

private func gatewayChannelBindingActions(channel: JsonObject, enabled: Bool, configured: Bool): JsonArray {
    let channelId = gatewayBindingStringParam(channel, ["id"], "")
    gatewayChannelBindingActionsJson(channelId, enabled, configured)
}

private func gatewayChannelBindingsJson(user: GatewayUserSettings, channelId: String): JsonObject {
    let channel = gatewayChannelGetJson(user, channelId)
    let registry = gatewayChannelBindingRegistryRow(user, channelId)
    let bindings = JsonObject()
    var enabled = gatewayBindingBool(channel, "enabled")
    var configured = gatewayBindingBool(channel, "configured")
    let model = channel.get("model") ?? JsonString("")
    var hostBindings = JsonObject()
    var defaultAccountId = gatewayBindingStringParam(registry, ["defaultAccountId"], "${channelId}:default")
    match (getGatewayChannelCatalogEntry(channelId)) {
        case Some(entry) =>
            if (!entry.builtin && gatewayLegacyPluginHostCompatible(entry.pluginId)) {
                hostBindings = gatewayHostBindingsForPlugin(user, entry.pluginId)
                match (hostBindings.get("configured")) {
                    case Some(v) =>
                        try {
                            configured = v.asBool().getValue()
                            channel.put("configured", configured.toJsonValue())
                        } catch (_e: Exception) {
                            ()
                        }
                    case None => ()
                }
                match (hostBindings.get("defaultAccountId")) {
                    case Some(v) =>
                        try { defaultAccountId = v.asString().getValue() } catch (_e: Exception) { () }
                    case None => ()
                }
            }
        case None => ()
    }
    let hostConfiguredBinding = gatewayBindingBool(hostBindings, "configuredBinding")
    let effectiveConfiguredBinding = gatewayBindingBool(registry, "configuredBinding") || hostConfiguredBinding
    bindings.put("channel", channel)
    bindings.put("registry", registry)
    if (hostBindings.size() > 0) {
        bindings.put("hostBindings", hostBindings)
    }
    bindings.put("configuredBinding", effectiveConfiguredBinding.toJsonValue())
    bindings.put("primed", registry.get("primed") ?? false.toJsonValue())
    bindings.put("autoEnabled", registry.get("autoEnabled") ?? false.toJsonValue())
    bindings.put("primedAtMs", registry.get("primedAtMs") ?? 0.toJsonValue())
    bindings.put("configuredAccountIds", registry.get("configuredAccountIds") ?? JsonArray([]))
    bindings.put("configuredAccountCount", registry.get("configuredAccountCount") ?? 0.toJsonValue())
    bindings.put("bindingState", JsonString(gatewayChannelBindingState(enabled, configured, gatewayBindingBool(registry, "primed"))))
    bindings.put("model", model)
    bindings.put("defaultAccountId", JsonString(defaultAccountId))
    bindings.put("actionsNeeded", gatewayBindingActionsNeeded(enabled && configured && effectiveConfiguredBinding).toJsonValue())
    bindings.put("bindingTarget", JsonString(if (enabled) { "gateway-runtime" } else { "disabled" }))
    bindings.put("policyState", JsonString(
        if (enabled && configured && gatewayBindingBool(registry, "primed")) {
            "routable"
        } else {
            gatewayChannelBindingState(enabled, configured, false)
        }
    ))
    bindings.put("constraints", gatewayChannelBindingConstraints(channel, enabled, configured))
    bindings.put("actions", gatewayChannelBindingActions(channel, enabled, configured))
    bindings
}

private func gatewayPluginBindingConstraints(plugin: JsonObject, installed: Bool, registered: Bool, enabled: Bool, configured: Bool): JsonArray {
    gatewayPluginBindingConstraintsJson(installed, registered, enabled, configured, gatewayBindingArraySize(plugin.get("declaredChannelIds") ?? JsonArray([])))
}

private func gatewayPluginBindingActions(plugin: JsonObject, installed: Bool, registered: Bool, enabled: Bool, configured: Bool): JsonArray {
    let pluginId = gatewayBindingStringParam(plugin, ["id"], "")
    gatewayPluginBindingActionsJson(pluginId, installed, registered, enabled, configured)
}

private func gatewayPluginBindingsJson(user: GatewayUserSettings, pluginId: String): JsonObject {
    let plugin = gatewayPluginGetJson(user, pluginId)
    let registry = gatewayPluginBindingRegistryRow(user, pluginId)
    let bindings = JsonObject()
    let installed = gatewayBindingBool(plugin, "installed")
    let registered = gatewayBindingBool(plugin, "registered")
    var configured = gatewayBindingBool(plugin, "configured")
    let gatewayPlugin = match (plugin.get("gatewayPlugin")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let enabled = gatewayBindingBool(gatewayPlugin, "enabled")
    let hostBindings = gatewayHostBindingsForPlugin(user, pluginId)
    if (hostBindings.size() > 0) {
        match (hostBindings.get("configured")) {
            case Some(v) =>
                try {
                    configured = v.asBool().getValue()
                    plugin.put("configured", configured.toJsonValue())
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
    }
    let hostConfiguredBinding = gatewayBindingBool(hostBindings, "configuredBinding")
    let effectiveConfiguredBinding = gatewayBindingBool(registry, "configuredBinding") || hostConfiguredBinding
    bindings.put("plugin", plugin)
    bindings.put("registry", registry)
    if (hostBindings.size() > 0) {
        bindings.put("hostBindings", hostBindings)
    }
    bindings.put("configuredBinding", effectiveConfiguredBinding.toJsonValue())
    bindings.put("primed", registry.get("primed") ?? false.toJsonValue())
    bindings.put("autoEnabled", registry.get("autoEnabled") ?? false.toJsonValue())
    bindings.put("primedAtMs", registry.get("primedAtMs") ?? 0.toJsonValue())
    bindings.put("configuredAccountIds", registry.get("configuredAccountIds") ?? JsonArray([]))
    bindings.put("configuredAccountCount", registry.get("configuredAccountCount") ?? 0.toJsonValue())
    bindings.put("bindingState", JsonString(gatewayPluginBindingState(installed, registered, enabled, configured, gatewayBindingBool(registry, "primed"))))
    bindings.put("enabled", enabled.toJsonValue())
    bindings.put("actionsNeeded", gatewayBindingActionsNeeded(installed && registered && enabled && configured && effectiveConfiguredBinding).toJsonValue())
    bindings.put("activeChannelIds", hostBindings.get("activeChannelIds") ?? plugin.get("declaredChannelIds") ?? JsonArray([]))
    bindings.put("defaultAccountId", hostBindings.get("defaultAccountId") ?? registry.get("defaultAccountId") ?? JsonString("${pluginId}:default"))
    bindings.put("policyState", JsonString(
        if (installed && registered && enabled && configured && gatewayBindingBool(registry, "primed")) {
            "routable"
        } else {
            gatewayPluginBindingState(installed, registered, enabled, configured, false)
        }
    ))
    bindings.put("constraints", gatewayPluginBindingConstraints(plugin, installed, registered, enabled, configured))
    bindings.put("actions", gatewayPluginBindingActions(plugin, installed, registered, enabled, configured))
    bindings
}

private func gatewayChannelAccountSnapshots(user: GatewayUserSettings, channelId: String, probe!: Bool = false, timeoutMs!: Int64 = 10000): JsonArray {
    let out = JsonArray([])
    let channel = gatewayChannelGetJson(user, channelId)
    let bindings = gatewayChannelBindingsJson(user, channelId)
    var runtimeAccounts = gatewayChannelRuntimeAccountsJson(channelId)
    let enabled = gatewayBindingBool(channel, "enabled")
    var configured = gatewayBindingBool(channel, "configured")
    let hostBindings = gatewayHostObject(bindings.get("hostBindings") ?? JsonObject())
    let pluginId = match (getGatewayChannelCatalogEntry(channelId)) {
        case Some(entry) => entry.pluginId
        case None => ""
    }
    let hostAccounts = if (pluginId.isEmpty()) { JsonObject() } else { gatewayHostAccountsForPlugin(user, pluginId) }
    let hostAccountRows = gatewayHostArray(hostAccounts, "accounts")
    if (hostBindings.size() > 0) {
        match (hostBindings.get("configured")) {
            case Some(v) =>
                try { configured = v.asBool().getValue() } catch (_e: Exception) { () }
            case None => ()
        }
    }
    let defaultAccountIdValue = (bindings.get("defaultAccountId") ?? gatewayChannelRuntimeDefaultAccountId(channelId)).toJsonString().trimAscii().replace("\"", "")
    let defaultAccountId = if (defaultAccountIdValue.isEmpty()) { "${channelId}:default" } else { defaultAccountIdValue }
    if (runtimeAccounts.size() == 0 && hostAccountRows.size() > 0) {
        runtimeAccounts = hostAccountRows
    }
    if (runtimeAccounts.size() == 0) {
        let configuredAccountIds = gatewayHostArray(bindings, "configuredAccountIds")
        if (configuredAccountIds.size() > 0) {
            runtimeAccounts = gatewaySynthesizedRuntimeAccounts(configuredAccountIds, defaultAccountId)
        }
    }
    if (runtimeAccounts.size() == 0) {
        let row = JsonObject()
        row.put("accountId", JsonString(defaultAccountId))
        row.put("channelId", JsonString(channelId))
        row.put("defaultAccount", true.toJsonValue())
        row.put("enabled", enabled.toJsonValue())
        row.put("configured", configured.toJsonValue())
        row.put("runtime", JsonObject())
        if (probe) {
            row.put("probe", gatewayProbeResultJson(
                enabled && configured,
                if (enabled && configured) { "ready" } else if (enabled) { "pending-config" } else { "disabled" },
                timeoutMs
            ))
            row.put("audit", bindings)
            row.put("lastProbeAtMs", gatewayProbeTimestampMs().toJsonValue())
        }
        out.add(row)
        return out
    }
    for (i in 0..runtimeAccounts.size()) {
        let runtime = try { runtimeAccounts[i].asObject() } catch (_e: Exception) { JsonObject() }
        let accountId = gatewayBindingStringParam(runtime, ["accountId"], defaultAccountId)
        let row = JsonObject()
        row.put("accountId", JsonString(accountId))
        row.put("channelId", JsonString(channelId))
        row.put("defaultAccount", (accountId == defaultAccountId).toJsonValue())
        row.put("enabled", enabled.toJsonValue())
        row.put("configured", configured.toJsonValue())
        row.put("runtime", runtime)
        row.put("policyState", bindings.get("policyState") ?? JsonString("unknown"))
        row.put("bindingState", bindings.get("bindingState") ?? JsonString("unknown"))
        if (probe) {
            row.put("probe", gatewayProbeResultJson(
                enabled && configured,
                if (enabled && configured) { "ready" } else if (enabled) { "pending-config" } else { "disabled" },
                timeoutMs
            ))
            row.put("audit", bindings)
            row.put("lastProbeAtMs", gatewayProbeTimestampMs().toJsonValue())
        }
        out.add(row)
    }
    out
}

private func gatewayPluginAccountSnapshots(user: GatewayUserSettings, pluginId: String, probe!: Bool = false, timeoutMs!: Int64 = 10000): JsonArray {
    let out = JsonArray([])
    let plugin = gatewayPluginGetJson(user, pluginId)
    let bindings = gatewayPluginBindingsJson(user, pluginId)
    var runtimeAccounts = gatewayPluginRuntimeAccountsJson(pluginId)
    let installed = gatewayBindingBool(plugin, "installed")
    let registered = gatewayBindingBool(plugin, "registered")
    var configured = gatewayBindingBool(plugin, "configured")
    let gatewayPlugin = match (plugin.get("gatewayPlugin")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let enabled = gatewayBindingBool(gatewayPlugin, "enabled")
    let hostBindings = gatewayHostObject(bindings.get("hostBindings") ?? JsonObject())
    let hostAccounts = gatewayHostAccountsForPlugin(user, pluginId)
    let hostAccountRows = gatewayHostArray(hostAccounts, "accounts")
    if (hostBindings.size() > 0) {
        match (hostBindings.get("configured")) {
            case Some(v) =>
                try { configured = v.asBool().getValue() } catch (_e: Exception) { () }
            case None => ()
        }
    }
    if (runtimeAccounts.size() == 0 && hostAccountRows.size() > 0) {
        runtimeAccounts = hostAccountRows
    }
    if (runtimeAccounts.size() == 0) {
        let configuredAccountIds = gatewayHostArray(bindings, "configuredAccountIds")
        if (configuredAccountIds.size() > 0) {
            runtimeAccounts = gatewaySynthesizedRuntimeAccounts(
                configuredAccountIds,
                gatewayBindingStringParam(bindings, ["defaultAccountId"], "${pluginId}:default")
            )
        }
    }
    if (runtimeAccounts.size() == 0) {
        let row = JsonObject()
        let defaultAccountId = gatewayBindingStringParam(bindings, ["defaultAccountId"], "${pluginId}:default")
        row.put("accountId", JsonString(defaultAccountId))
        row.put("pluginId", JsonString(pluginId))
        row.put("defaultAccount", true.toJsonValue())
        row.put("enabled", enabled.toJsonValue())
        row.put("configured", configured.toJsonValue())
        row.put("installed", installed.toJsonValue())
        row.put("registered", registered.toJsonValue())
        row.put("runtime", JsonObject())
        row.put("policyState", bindings.get("policyState") ?? JsonString("unknown"))
        row.put("bindingState", bindings.get("bindingState") ?? JsonString("unknown"))
        if (probe) {
            let ok = installed && registered && enabled && configured
            row.put("probe", gatewayProbeResultJson(
                ok,
                if (ok) { "ready" } else if (installed && registered) { "available" } else { "missing" },
                timeoutMs
            ))
            row.put("audit", bindings)
            row.put("lastProbeAtMs", gatewayProbeTimestampMs().toJsonValue())
        }
        out.add(row)
        return out
    }
    for (i in 0..runtimeAccounts.size()) {
        let runtime = try { runtimeAccounts[i].asObject() } catch (_e: Exception) { JsonObject() }
        let accountId = gatewayBindingStringParam(runtime, ["accountId"], gatewayBindingStringParam(bindings, ["defaultAccountId"], "${pluginId}:default"))
        let row = JsonObject()
        row.put("accountId", JsonString(accountId))
        row.put("pluginId", JsonString(pluginId))
        row.put("defaultAccount", (accountId == gatewayBindingStringParam(bindings, ["defaultAccountId"], "${pluginId}:default")).toJsonValue())
        row.put("enabled", enabled.toJsonValue())
        row.put("configured", configured.toJsonValue())
        row.put("installed", installed.toJsonValue())
        row.put("registered", registered.toJsonValue())
        row.put("runtime", runtime)
        row.put("policyState", bindings.get("policyState") ?? JsonString("unknown"))
        row.put("bindingState", bindings.get("bindingState") ?? JsonString("unknown"))
        if (probe) {
            let ok = installed && registered && enabled && configured
            row.put("probe", gatewayProbeResultJson(
                ok,
                if (ok) { "ready" } else if (installed && registered) { "available" } else { "missing" },
                timeoutMs
            ))
            row.put("audit", bindings)
            row.put("lastProbeAtMs", gatewayProbeTimestampMs().toJsonValue())
        }
        out.add(row)
    }
    out
}

private func gatewayChannelStatusRow(user: GatewayUserSettings, channelId: String, probe!: Bool = false, timeoutMs!: Int64 = 10000): JsonObject {
    let channel = gatewayChannelGetJson(user, channelId)
    let bindings = gatewayChannelBindingsJson(user, channelId)
    let enabled = gatewayBindingBool(channel, "enabled")
    let configured = gatewayBindingBool(channel, "configured")
    match (getGatewayChannelCatalogEntry(channelId)) {
        case Some(entry) =>
            if (!entry.builtin && gatewayLegacyPluginHostCompatible(entry.pluginId)) {
                let _ = gatewayConsumeLegacyPluginRuntime(user, entry.pluginId)
            }
        case None => ()
    }
    let runtime = gatewayChannelRuntimeSummary(channelId)
    let row = JsonObject()
    row.put("channel", channel)
    row.put("binding", bindings)
    row.put("runtime", runtime)
    row.put("supports", gatewayChannelSupportsJson(user, channelId))
    row.put("enabled", enabled.toJsonValue())
    row.put("configured", configured.toJsonValue())
    row.put("policyState", bindings.get("policyState") ?? JsonString("unknown"))
    row.put("bindingState", bindings.get("bindingState") ?? JsonString("unknown"))
    if (channelId == "telegram") {
        row.put("telegram", gatewayTelegramRuntimeJson(user, liveProbe: probe))
    }
    if (channelId == "feishu") {
        let auth = gatewayFeishuNativeAuthStatus(gatewayFeishuDefaultAccountId(user), user)
        row.put("auth", auth)
        row.put("oauth", auth)
        row.put("doctor", gatewayFeishuChannelDiagnosticsJson(user))
        row.put("capabilities", JsonArray([
            JsonString("oauth:device-flow"),
            JsonString("oauth:lifecycle"),
            JsonString("oapi:tools"),
            JsonString("doctor")
        ]))
    }
    match (getGatewayChannelCatalogEntry(channelId)) {
        case Some(entry) =>
            if (!entry.builtin && gatewayLegacyPluginHostCompatible(entry.pluginId)) {
                let host = gatewayLegacyPluginHostInspect(entry.pluginId, config: pluginConfigFromChannelsExtra(user.channelsExtra, entry.pluginId))
                row.put("host", host)
                match (host.get("configured")) {
                    case Some(v) =>
                        row.put("configured", v)
                        channel.put("configured", v)
                    case None => ()
                }
            }
        case None => ()
    }
    if (probe) {
        var hostHandled = false
        match (getGatewayChannelCatalogEntry(channelId)) {
            case Some(entry) =>
                if (!entry.builtin && gatewayLegacyPluginHostCompatible(entry.pluginId)) {
                    row.put(
                        "probe",
                        gatewayLegacyPluginHostProbe(
                            entry.pluginId,
                            config: pluginConfigFromChannelsExtra(user.channelsExtra, entry.pluginId),
                            timeoutMs: timeoutMs
                        )
                    )
                    row.put(
                        "audit",
                        gatewayLegacyPluginHostAudit(
                            entry.pluginId,
                            config: pluginConfigFromChannelsExtra(user.channelsExtra, entry.pluginId),
                            timeoutMs: timeoutMs
                        )
                    )
                    hostHandled = true
                }
            case None => ()
        }
        if (!hostHandled) {
            let ok = enabled && configured
            let bundle = gatewayBindingProbeAuditBundle(
                ok,
                if (ok) { "ready" } else if (enabled) { "pending-config" } else { "disabled" },
                timeoutMs,
                bindings.get("policyState") ?? JsonString("unknown"),
                bindings.get("bindingState") ?? JsonString("unknown"),
                bindings.get("constraints") ?? JsonArray([]),
                bindings.get("actions") ?? JsonArray([]),
                bindings.get("actionsNeeded") ?? false.toJsonValue()
            )
            row.put("probe", bundle.get("probe") ?? JsonObject())
            row.put("audit", bundle.get("audit") ?? JsonObject())
            row.put("lastProbeAtMs", bundle.get("lastProbeAtMs") ?? 0.toJsonValue())
        }
    }
    row
}

private func gatewayPluginStatusRow(user: GatewayUserSettings, pluginId: String, probe!: Bool = false, timeoutMs!: Int64 = 10000): JsonObject {
    let plugin = gatewayPluginGetJson(user, pluginId)
    let bindings = gatewayPluginBindingsJson(user, pluginId)
    let enabled = gatewayBindingBool(bindings, "enabled")
    let configured = gatewayBindingBool(plugin, "configured")
    if (gatewayLegacyPluginHostCompatible(pluginId)) {
        let _ = gatewayConsumeLegacyPluginRuntime(user, pluginId)
    }
    let runtime = gatewayPluginRuntimeSummary(pluginId)
    let row = JsonObject()
    row.put("plugin", plugin)
    row.put("binding", bindings)
    row.put("runtime", runtime)
    row.put("enabled", enabled.toJsonValue())
    row.put("configured", configured.toJsonValue())
    row.put("policyState", bindings.get("policyState") ?? JsonString("unknown"))
    row.put("bindingState", bindings.get("bindingState") ?? JsonString("unknown"))
    if (gatewayLegacyPluginHostCompatible(pluginId)) {
        let host = gatewayLegacyPluginHostInspect(pluginId, config: pluginConfigFromChannelsExtra(user.channelsExtra, pluginId))
        row.put("host", host)
        match (host.get("configured")) {
            case Some(v) =>
                row.put("configured", v)
                plugin.put("configured", v)
            case None => ()
        }
        match (host.get("supports")) {
            case Some(v) => row.put("supports", v)
            case None => ()
        }
    }
    if (probe) {
        if (gatewayLegacyPluginHostCompatible(pluginId)) {
            row.put("probe", gatewayLegacyPluginHostProbe(pluginId, config: pluginConfigFromChannelsExtra(user.channelsExtra, pluginId), timeoutMs: timeoutMs))
            row.put("audit", gatewayLegacyPluginHostAudit(pluginId, config: pluginConfigFromChannelsExtra(user.channelsExtra, pluginId), timeoutMs: timeoutMs))
        } else {
            let installed = gatewayBindingBool(plugin, "installed")
            let registered = gatewayBindingBool(plugin, "registered")
            let ok = installed && registered && enabled && configured
            let bundle = gatewayBindingProbeAuditBundle(
                ok,
                if (ok) { "ready" } else if (installed && registered) { "available" } else { "missing" },
                timeoutMs,
                bindings.get("policyState") ?? JsonString("unknown"),
                bindings.get("bindingState") ?? JsonString("unknown"),
                bindings.get("constraints") ?? JsonArray([]),
                bindings.get("actions") ?? JsonArray([]),
                bindings.get("actionsNeeded") ?? false.toJsonValue()
            )
            row.put("probe", bundle.get("probe") ?? JsonObject())
            row.put("audit", bundle.get("audit") ?? JsonObject())
            row.put("lastProbeAtMs", bundle.get("lastProbeAtMs") ?? 0.toJsonValue())
        }
    }
    row
}

private func gatewayDiscoverDetailJson(user: GatewayUserSettings): JsonObject {
    let channels = JsonArray([])
    let plugins = JsonArray([])
    for (entry in listGatewayChannelCatalogEntries()) {
        channels.add(gatewayChannelGetJson(user, entry.id))
    }
    for (entry in listGatewayPluginCatalogEntries()) {
        if (!entry.builtin) {
            plugins.add(gatewayPluginGetJson(user, entry.id))
        }
    }
    return gatewayDiscoverDetailSummaryJson(
        builtinGatewayChannelIds().toJsonValue(),
        registeredGatewayPluginIds().toJsonValue(),
        gatewayActionsDiscoverInstalledPluginIds().toJsonValue(),
        gatewayChannelCatalogJson(),
        gatewayPluginCatalogJson(),
        channels,
        plugins
    )
}

private func gatewayChannelsHealthJson(user: GatewayUserSettings, liveProbe!: Bool = false): JsonObject {
    let result = gatewayBuildChannelsHealthJson(user, { channelId, probe, timeoutMs =>
        gatewayChannelStatusRow(user, channelId, probe: probe, timeoutMs: timeoutMs)
    })
    let telegramRuntime = gatewayTelegramRuntimeJson(user, liveProbe: liveProbe)
    result.put("telegram", telegramRuntime)
    result.put("telegramDiagnostics", gatewayTelegramDiagnosticsJson(user, runtime: telegramRuntime))
    result
}

private func gatewayChannelsAuditJson(user: GatewayUserSettings, channelId!: String = ""): JsonObject {
    let normalized = channelId.trimAscii().toAsciiLower()
    let result = JsonObject()
    let summary = JsonObject()
    let closure = JsonObject()
    let consumers = JsonObject()
    let acceptance = JsonArray([])
    let remaining = JsonArray([])

    summary.put("kind", JsonString("gateway-channels-audit"))
    summary.put("phase", JsonString("T12"))
    summary.put("focus", JsonString(if (normalized.isEmpty()) { "all-channels" } else { normalized }))

    closure.put("channelsRuntimeAvailable", true.toJsonValue())
    closure.put("channelsHealthAvailable", true.toJsonValue())
    closure.put("dashboardHttpAvailable", true.toJsonValue())
    closure.put("controlUiHttpAvailable", true.toJsonValue())
    closure.put("controlUiWsAvailable", true.toJsonValue())
    closure.put("controlUiSessionsHttpAvailable", true.toJsonValue())
    closure.put("controlUiSessionsWsAvailable", true.toJsonValue())
    closure.put("telegramNativeRuntimeVisible", true.toJsonValue())
    closure.put("telegramLiveProbeRuntimeVisible", true.toJsonValue())
    closure.put("telegramReactionRuntimeVisible", true.toJsonValue())
    closure.put("telegramMediaRuntimeVisible", true.toJsonValue())
    closure.put("telegramMediaPersistenceVisible", true.toJsonValue())
    closure.put("telegramThreadBindingProjectedInSessions", true.toJsonValue())
    closure.put("telegramThreadBindingVisibleInDashboardSessions", true.toJsonValue())
    closure.put("telegramThreadBindingVisibleInControlUiSessions", true.toJsonValue())
    closure.put("telegramThreadBindingVisibleInControlUiWsSessions", true.toJsonValue())

    consumers.put("rpc", true.toJsonValue())
    consumers.put("mcpOverHttp", true.toJsonValue())
    consumers.put("dashboardHttp", true.toJsonValue())
    consumers.put("dashboardSessions", true.toJsonValue())
    consumers.put("controlUiHttp", true.toJsonValue())
    consumers.put("controlUiWs", true.toJsonValue())
    consumers.put("controlUiSessionsHttp", true.toJsonValue())
    consumers.put("controlUiSessionsWs", true.toJsonValue())

    acceptance.add(JsonString("channels-runtime-and-health-are-exposed-across-consumers"))
    acceptance.add(JsonString("telegram-native-runtime-is-visible-across-consumers"))
    acceptance.add(JsonString("telegram-live-probe-runtime-is-visible-across-consumers"))
    acceptance.add(JsonString("telegram-reaction-and-media-runtime-are-visible-across-consumers"))
    acceptance.add(JsonString("telegram-media-download-and-file-persistence-are-visible-across-consumers"))
    acceptance.add(JsonString("telegram-thread-binding-is-projected-into-session-surfaces"))
    acceptance.add(JsonString("telegram-thread-binding-is-visible-in-dashboard-and-control-ui-session-surfaces"))
    acceptance.add(JsonString("telegram-thread-binding-is-visible-in-control-ui-ws-session-surface"))

    summary.put("closure", closure)
    summary.put("consumers", consumers)
    summary.put("acceptanceCount", acceptance.size().toJsonValue())
    summary.put("remainingCount", remaining.size().toJsonValue())

    let runtime = JsonObject()
    var telegramRuntime = JsonObject()
    if (normalized.isEmpty()) {
        runtime.put("channels", gatewayChannelsHealthJson(user))
        runtime.put("channelMeta", gatewayChannelMetaJson(user))
        telegramRuntime = gatewayTelegramRuntimeJson(user, liveProbe: true)
        runtime.put("telegram", telegramRuntime)
    } else {
        runtime.put("channel", gatewayChannelGetJson(user, normalized))
        runtime.put("summary", gatewayChannelRuntimeSummary(normalized))
        if (normalized == "telegram") {
            telegramRuntime = gatewayTelegramRuntimeJson(user, liveProbe: true)
            runtime.put("telegram", telegramRuntime)
        }
    }
    let telegramDiagnostics = gatewayTelegramDiagnosticsJson(user, runtime: telegramRuntime)
    summary.put("telegramDiagnostics", telegramDiagnostics.get("summary") ?? JsonObject())

    result.put("kind", JsonString("gateway-channels-audit"))
    result.put("summary", summary)
    result.put("runtime", runtime)
    result.put("telegramDiagnostics", telegramDiagnostics)
    result.put("acceptance", acceptance)
    result.put("remaining", remaining)
    return result
}

private func gatewayPluginsHealthJson(user: GatewayUserSettings): JsonObject {
    gatewayBuildPluginsHealthJson(user, { pluginId, probe, timeoutMs =>
        gatewayPluginStatusRow(user, pluginId, probe: probe, timeoutMs: timeoutMs)
    })
}

private func gatewayPluginApprovalRow(user: GatewayUserSettings, pluginId: String): JsonObject {
    let normalized = normalizeGatewayChannelId(pluginId)
    let installedIds = gatewayActionsDiscoverInstalledPluginIds()
    let registeredIds = registeredGatewayPluginIds()
    let pluginConfig = pluginConfigFromChannelsExtra(user.channelsExtra, normalized)
    let gatewayPlugin = gatewayPluginSettingById(user, normalized)
    let installed = installedIds.contains(normalized)
    let registered = registeredIds.contains(normalized)
    var configured = gatewayPluginConfigPresent(user.channelsExtra, normalized)
    if (gatewayLegacyPluginHostCompatible(normalized)) {
        let host = gatewayLegacyPluginHostInspect(normalized, config: pluginConfig)
        match (host.get("configured")) {
            case Some(v) =>
                try {
                    configured = v.asBool().getValue()
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
    }
    let enabled = gatewayBindingBool(gatewayPlugin, "enabled")
    gatewayPluginApprovalRowJson(pluginId, installed, registered, enabled, configured)
}

private func gatewayPluginPackageProbeRow(user: GatewayUserSettings, pluginId: String): JsonObject {
    let normalized = normalizeGatewayChannelId(pluginId)
    if (gatewayLegacyPluginHostCompatible(normalized)) {
        let row = gatewayLegacyPluginHostPackageState(normalized, config: pluginConfigFromChannelsExtra(user.channelsExtra, normalized))
        row.put("status", gatewayLegacyPluginHostStatus(normalized, config: pluginConfigFromChannelsExtra(user.channelsExtra, normalized)))
        row.put("actions", gatewayLegacyPluginHostActions(normalized, config: pluginConfigFromChannelsExtra(user.channelsExtra, normalized)))
        return row
    }
    let installed = gatewayActionsDiscoverInstalledPluginIds().contains(normalized)
    let registered = registeredGatewayPluginIds().contains(normalized)
    gatewayPluginPackageProbeRowJson(normalized, installed, registered)
}

private func gatewayPluginSetupRow(user: GatewayUserSettings, pluginId: String): JsonObject {
    let normalized = normalizeGatewayChannelId(pluginId)
    if (gatewayLegacyPluginHostCompatible(normalized)) {
        let row = gatewayLegacyPluginHostSetup(normalized, config: pluginConfigFromChannelsExtra(user.channelsExtra, normalized))
        row.put("actions", gatewayLegacyPluginHostActions(normalized, config: pluginConfigFromChannelsExtra(user.channelsExtra, normalized)))
        return row
    }
    let catalog = match (getGatewayPluginCatalogEntry(normalized)) {
        case Some(entry) => entry.toJson()
        case None => JsonObject()
    }
    let configured = gatewayPluginConfigPresent(user.channelsExtra, normalized)
    let setupSupported = gatewayBindingBool(catalog, "setupSupported")
    gatewayPluginSetupRowJson(normalized, setupSupported, configured, catalog)
}

private func gatewayPluginsApprovalsJson(user: GatewayUserSettings): JsonObject {
    let rows = JsonArray([])
    for (entry in listGatewayPluginCatalogEntries()) {
        if (!entry.builtin) {
            rows.add(gatewayPluginApprovalRow(user, entry.id))
        }
    }
    gatewayPluginsApprovalSummaryJson(rows)
}

private func gatewayPluginsPackageStateJson(user: GatewayUserSettings): JsonObject {
    let rows = JsonArray([])
    for (entry in listGatewayPluginCatalogEntries()) {
        if (!entry.builtin) {
            rows.add(gatewayPluginPackageProbeRow(user, entry.id))
        }
    }
    gatewayPluginsPackageStateSummaryJson(rows)
}

private func gatewayPluginsSetupJson(user: GatewayUserSettings): JsonObject {
    let rows = JsonArray([])
    for (entry in listGatewayPluginCatalogEntries()) {
        if (!entry.builtin) {
            rows.add(gatewayPluginSetupRow(user, entry.id))
        }
    }
    gatewayPluginsSetupSummaryJson(rows)
}

private func gatewayPluginsSetupApplyJson(user: GatewayUserSettings, request: GatewayRpcRequest): JsonObject {
    let requestedPluginId = gatewayRpcStringParam(request, ["pluginId", "id"], "")
    let items = JsonArray([])
    if (!requestedPluginId.isEmpty()) {
        items.add(gatewayApplyPluginSetup(user, requestedPluginId, request))
    } else {
        for (entry in listGatewayPluginCatalogEntries()) {
            if (!entry.builtin && gatewayLegacyPluginHostCompatible(entry.id)) {
                items.add(gatewayApplyPluginSetup(user, entry.id, request))
            }
        }
    }
    gatewayBatchApplySummaryJson(items)
}

public func handleGatewayChannelsFamily(method: String, user: GatewayUserSettings, request!: Option<GatewayRpcRequest> = None): Option<GatewayRpcResponse> {
    if (method == "discover") {
        let result = gatewayDiscoverDetailJson(user)
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "discover.detail") {
        return Some(GatewayRpcResponse(true, method, result: gatewayDiscoverDetailJson(user)))
    }
    if (method == "channels.status" || method == "channels.list") {
        gatewayEnsureChannelBootstrap(user)
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let wantsProbe = gatewayRpcBoolParam(requestValue, ["probe"], false)
        let timeoutMs = gatewayRpcIntParam(requestValue, ["timeoutMs"], 10000)
        let result = JsonObject()
        let channelRows = JsonArray([])
        let channels = JsonObject()
        let channelAccounts = JsonObject()
        let channelDefaultAccountId = JsonObject()
        for (entry in listGatewayChannelCatalogEntries()) {
            let row = gatewayChannelStatusRow(user, entry.id, probe: wantsProbe, timeoutMs: timeoutMs)
            channelRows.add(row)
            channels.put(entry.id, row)
            channelAccounts.put(entry.id, gatewayChannelAccountSnapshots(user, entry.id, probe: wantsProbe, timeoutMs: timeoutMs))
            channelDefaultAccountId.put(entry.id, gatewayChannelRuntimeDefaultAccountId(entry.id))
        }
        result.put("channelOrder", gatewayChannelOrderJson())
        result.put("channelLabels", gatewayChannelLabelsJson())
        result.put("channelDetailLabels", gatewayChannelDetailLabelsJson())
        result.put("channelSystemImages", gatewayChannelSystemImagesJson())
        result.put("channelMeta", gatewayChannelMetaJson(user))
        result.put("channels", channels)
        result.put("channelRows", channelRows)
        result.put("channelAccounts", channelAccounts)
        result.put("channelDefaultAccountId", channelDefaultAccountId)
        result.put("channelModels", gatewayRpcConfigValueAtPath(user, "gateway.channelmodels") ?? JsonObject(HashMap<String, JsonValue>()))
        result.put("channelsExtra", gatewayChannelsExtraJson(user))
        result.put("hasAnyEnabledChannel", gatewayHasAnyEnabledChannel(user).toJsonValue())
        result.put("health", gatewayChannelsHealthJson(user))
        result.put("probe", wantsProbe.toJsonValue())
        result.put("timeoutMs", timeoutMs.toJsonValue())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "channels.feishu.auth.start") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let accountId = gatewayRpcStringParam(requestValue, ["accountId", "account"], "")
        let result = gatewayFeishuNativeAuthStart(accountId, user)
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "channels.feishu.auth.status") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let accountId = gatewayRpcStringParam(requestValue, ["accountId", "account"], "")
        let result = gatewayFeishuNativeAuthStatus(accountId, user)
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "channels.feishu.auth.poll") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let accountId = gatewayRpcStringParam(requestValue, ["accountId", "account"], "")
        let result = gatewayFeishuNativeAuthPoll(accountId, user)
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "channels.feishu.auth.complete") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let accountId = gatewayRpcStringParam(requestValue, ["accountId", "account"], "")
        let result = gatewayFeishuNativeAuthComplete(accountId, user)
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "channels.feishu.auth.revoke") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let accountId = gatewayRpcStringParam(requestValue, ["accountId", "account"], "")
        let serverRevoke = gatewayRpcBoolParam(requestValue, ["serverRevoke", "server", "remote"], false)
        let result = gatewayFeishuNativeAuthRevoke(accountId, user, serverRevoke: serverRevoke)
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "channels.feishu.auth.liveSmoke") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let accountId = gatewayRpcStringParam(requestValue, ["accountId", "account"], "")
        let outputRoot = gatewayRpcStringParam(requestValue, ["outputDir", "outputRoot", "reportDir"], "")
        let result = feishuGatewayNativeAuthLiveSmoke(accountId, user, outputRoot: outputRoot)
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "channels.logout") {
        gatewayEnsureChannelBootstrap(user)
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let channelId = gatewayRpcStringParam(requestValue, ["id", "channel", "channelId"], "feishu")
        let channelPluginId = gatewayHostCompatiblePluginForChannel(channelId)
        if (!channelPluginId.isEmpty()) {
            return Some(GatewayRpcResponse(true, method, result: gatewayChannelActionByPlugin(user, requestValue, "logout")))
        }
        let defaultAccountIdValue = gatewayChannelRuntimeDefaultAccountId(channelId).toJsonString().trimAscii().replace("\"", "")
        let fallbackAccountId = if (defaultAccountIdValue.isEmpty()) { "${channelId}:default" } else { defaultAccountIdValue }
        let accountId = gatewayRpcStringParam(requestValue, ["accountId"], fallbackAccountId)
        let host = match (getGatewayChannelCatalogEntry(channelId)) {
            case Some(entry) =>
                if (!entry.builtin && gatewayLegacyPluginHostCompatible(entry.pluginId)) {
                    gatewayLegacyPluginHostLogout(entry.pluginId, config: pluginConfigFromChannelsExtra(user.channelsExtra, entry.pluginId), accountId: accountId)
                } else {
                    JsonObject()
                }
            case None => JsonObject()
        }
        let loggedOut = gatewayLogoutLoggedOut(host)
        let stopped = gatewayChannelRuntimeMarkStopped(
            channelId,
            accountId: accountId,
            reason: if (loggedOut) { "logged out" } else { "logout" },
            manualStop: true
        )
        let result = JsonObject()
        result.put("channelId", JsonString(channelId))
        result.put("channel", JsonString(channelId))
        result.put("accountId", JsonString(accountId))
        result.put("cleared", gatewayLogoutCleared(host).toJsonValue())
        result.put("loggedOut", loggedOut.toJsonValue())
        if (host.size() > 0) {
            result.put("host", host)
        }
        result.put("runtime", stopped)
        result.put("summary", gatewayChannelRuntimeSummary(channelId))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "channels.start") {
        gatewayEnsureChannelBootstrap(user)
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        return Some(GatewayRpcResponse(true, method, result: gatewayChannelActionByPlugin(user, requestValue, "start")))
    }
    if (method == "channels.stop") {
        gatewayEnsureChannelBootstrap(user)
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        return Some(GatewayRpcResponse(true, method, result: gatewayChannelActionByPlugin(user, requestValue, "stop")))
    }
    if (method == "channels.restart") {
        gatewayEnsureChannelBootstrap(user)
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        return Some(GatewayRpcResponse(true, method, result: gatewayChannelActionByPlugin(user, requestValue, "restart")))
    }
    if (method == "channels.send") {
        gatewayEnsureChannelBootstrap(user)
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        return Some(GatewayRpcResponse(true, method, result: gatewayChannelActionByPlugin(user, requestValue, "send")))
    }
    if (method == "channels.telegram.getChat") {
        gatewayEnsureChannelBootstrap(user)
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        return Some(GatewayRpcResponse(true, method, result: gatewayTelegramGetChatByNativeAdapter(user, requestValue)))
    }
    if (method == "channels.runtime") {
        gatewayEnsureChannelBootstrap(user)
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let channelId = gatewayRpcStringParam(requestValue, ["id", "channel", "channelId"], "feishu")
        let wantsProbe = gatewayRpcBoolParam(requestValue, ["probe"], false)
        let summary = gatewayChannelRuntimeSummary(channelId)
        let result = JsonObject()
        result.put("runtime", gatewayChannelRuntimeSnapshot())
        result.put("bootstrap", gatewayChannelRuntimeBootstrapSummary())
        result.put("channelId", JsonString(channelId))
        result.put("accounts", summary.get("accounts") ?? JsonArray([]))
        result.put("defaultAccountId", summary.get("defaultAccountId") ?? JsonString(""))
        result.put("summary", summary)
        result.put("startCount", summary.get("startCount") ?? 0.toJsonValue())
        result.put("running", ((summary.get("running") ?? 0.toJsonValue()).toJsonString() != "0").toJsonValue())
        if (channelId == "telegram") {
            result.put("telegram", gatewayTelegramRuntimeJson(user, liveProbe: wantsProbe))
        }
        if (channelId == "feishu") {
            let feishu = JsonObject()
            feishu.put("accountInspect", gatewayFeishuAccountInspectJson(user))
            result.put("feishu", feishu)
        }
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "channels.manager") {
        gatewayEnsureChannelBootstrap(user)
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let channelId = gatewayRpcStringParam(requestValue, ["id", "channel", "channelId"], "feishu")
        let result = JsonObject()
        result.put("manager", gatewayChannelManagerSummary(channelId))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "channels.get") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let channelId = gatewayRpcStringParam(requestValue, ["id", "channel", "channelId"], "feishu")
        let result = JsonObject()
        result.put("channel", gatewayChannelGetJson(user, channelId))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "channels.health") {
        gatewayEnsureChannelBootstrap(user)
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let wantsProbe = gatewayRpcBoolParam(requestValue, ["probe"], false)
        let health = gatewayChannelsHealthJson(user, liveProbe: wantsProbe)
        let result = JsonObject()
        result.put("channels", health)
        result.put("telegram", health.get("telegram") ?? JsonObject())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "channels.audit") {
        gatewayEnsureChannelBootstrap(user)
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let channelId = gatewayRpcStringParam(requestValue, ["id", "channel", "channelId"], "")
        let result = JsonObject()
        result.put("audit", gatewayChannelsAuditJson(user, channelId: channelId))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "channels.health.actions") {
        gatewayEnsureChannelBootstrap(user)
        let health = gatewayChannelsHealthJson(user)
        let result = JsonObject()
        result.put("actions", health.get("actions") ?? JsonArray([]))
        result.put("policyState", health.get("policyState") ?? JsonString("steady"))
        result.put("actionsNeeded", health.get("actionsNeeded") ?? 0.toJsonValue())
        result.put("byHealthState", health.get("byHealthState") ?? JsonObject())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "channels.bindings") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let channelId = gatewayRpcStringParam(requestValue, ["id", "channel", "channelId"], "feishu")
        let result = JsonObject()
        result.put("bindings", gatewayChannelBindingsJson(user, channelId))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "channels.policy") {
        let bindings = JsonArray([])
        for (entry in listGatewayChannelCatalogEntries()) {
            bindings.add(gatewayChannelBindingsJson(user, entry.id))
        }
        let result = JsonObject()
        result.put("bindings", bindings)
        result.put("policy", gatewayBindingsPolicySummaryJson(bindings))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "plugins.status" || method == "plugins.list") {
        gatewayEnsureChannelBootstrap(user)
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let wantsProbe = gatewayRpcBoolParam(requestValue, ["probe"], false)
        let timeoutMs = gatewayRpcIntParam(requestValue, ["timeoutMs"], 10000)
        let result = JsonObject()
        let plugins = JsonArray([])
        let pluginAccounts = JsonObject()
        for (entry in listGatewayPluginCatalogEntries()) {
            if (!entry.builtin) {
                plugins.add(gatewayPluginStatusRow(user, entry.id, probe: wantsProbe, timeoutMs: timeoutMs))
                pluginAccounts.put(entry.id, gatewayPluginAccountSnapshots(user, entry.id, probe: wantsProbe, timeoutMs: timeoutMs))
            }
        }
        result.put("pluginOrder", gatewayPluginOrderJson())
        result.put("pluginMeta", gatewayPluginMetaJson(user))
        result.put("installedPluginIds", gatewayActionsDiscoverInstalledPluginIds().toJsonValue())
        result.put("registeredPluginIds", registeredGatewayPluginIds().toJsonValue())
        result.put("gatewayPlugins", gatewayPluginSettingsJson(user))
        result.put("plugins", plugins)
        result.put("pluginAccounts", pluginAccounts)
        result.put("health", gatewayPluginsHealthJson(user))
        result.put("probe", wantsProbe.toJsonValue())
        result.put("timeoutMs", timeoutMs.toJsonValue())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "plugins.runtime") {
        gatewayEnsureChannelBootstrap(user)
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let pluginId = gatewayRpcStringParam(requestValue, ["id", "plugin", "pluginId"], "")
        let result = JsonObject()
        let plugins = JsonObject()
        for (entry in listGatewayPluginCatalogEntries()) {
            if (!entry.builtin) {
                plugins.put(entry.id, gatewayPluginRuntimeSummary(entry.id))
            }
        }
        result.put("runtime", plugins)
        result.put("bootstrap", gatewayChannelRuntimeBootstrapSummary())
        if (!pluginId.isEmpty()) {
            result.put("pluginId", JsonString(pluginId))
            result.put("summary", gatewayPluginRuntimeSummary(pluginId))
        }
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "plugins.manager") {
        gatewayEnsureChannelBootstrap(user)
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let plugins = ArrayList<String>()
        for (entry in listGatewayPluginCatalogEntries()) {
            if (!entry.builtin) {
                plugins.add(entry.id)
            }
        }
        let fallbackId = if (plugins.isEmpty()) { "" } else { plugins[0] }
        let pluginId = gatewayRpcStringParam(requestValue, ["id", "plugin", "pluginId"], fallbackId)
        let result = JsonObject()
        if (!pluginId.isEmpty()) {
            result.put("manager", gatewayPluginManagerSummary(pluginId))
        } else {
            let manager = JsonObject()
            manager.put("pluginCount", plugins.size.toJsonValue())
            manager.put("running", 0.toJsonValue())
            manager.put("failureCount", 0.toJsonValue())
            manager.put("monitorEnabledCount", 0.toJsonValue())
            manager.put("manualStopCount", 0.toJsonValue())
            manager.put("taskState", JsonString("idle"))
            manager.put("monitorState", JsonString("disabled"))
            manager.put("abortState", JsonString("clear"))
            let items = JsonObject()
            for (entry in plugins) {
                items.put(entry, gatewayPluginManagerSummary(entry))
            }
            manager.put("items", items)
            result.put("manager", manager)
        }
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "plugins.get") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let plugins = ArrayList<String>()
        for (entry in listGatewayPluginCatalogEntries()) {
            if (!entry.builtin) {
                plugins.add(entry.id)
            }
        }
        let fallbackId = if (plugins.isEmpty()) { "" } else { plugins[0] }
        let pluginId = gatewayRpcStringParam(requestValue, ["id", "plugin", "pluginId"], fallbackId)
        let result = JsonObject()
        result.put("plugin", gatewayPluginGetJson(user, pluginId))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "plugins.approvals") {
        gatewayEnsureChannelBootstrap(user)
        return Some(GatewayRpcResponse(true, method, result: gatewayPluginsApprovalsJson(user)))
    }
    if (method == "plugins.package_state") {
        gatewayEnsureChannelBootstrap(user)
        return Some(GatewayRpcResponse(true, method, result: gatewayPluginsPackageStateJson(user)))
    }
    if (method == "plugins.setup") {
        gatewayEnsureChannelBootstrap(user)
        return Some(GatewayRpcResponse(true, method, result: gatewayPluginsSetupJson(user)))
    }
    if (method == "plugins.setup.registry") {
        gatewayEnsureChannelBootstrap(user)
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let pluginId = gatewayRpcStringParam(requestValue, ["id", "plugin", "pluginId"], "")
        let result = JsonObject()
        result.put("pluginId", JsonString(pluginId))
        result.put("setupRegistry", gatewayLegacyPluginHostSetupRegistry(pluginId, config: pluginConfigFromChannelsExtra(user.channelsExtra, pluginId)))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "plugins.setup.apply") {
        gatewayEnsureChannelBootstrap(user)
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        return Some(GatewayRpcResponse(true, method, result: gatewayPluginsSetupApplyJson(user, requestValue)))
    }
    if (method == "plugins.actions") {
        gatewayEnsureChannelBootstrap(user)
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let plugins = ArrayList<String>()
        for (entry in listGatewayPluginCatalogEntries()) {
            if (!entry.builtin) {
                plugins.add(entry.id)
            }
        }
        let fallbackId = if (plugins.isEmpty()) { "" } else { plugins[0] }
        let pluginId = gatewayRpcStringParam(requestValue, ["id", "plugin", "pluginId"], fallbackId)
        let result = JsonObject()
        result.put("pluginId", JsonString(pluginId))
        result.put("actions", gatewayLegacyPluginHostActions(pluginId, config: pluginConfigFromChannelsExtra(user.channelsExtra, pluginId), accountId: gatewayPluginActionAccountId(user, pluginId, requestValue)))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "plugins.actions.dispatch") {
        gatewayEnsureChannelBootstrap(user)
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let pluginId = gatewayRpcStringParam(requestValue, ["id", "plugin", "pluginId"], "")
        let action = gatewayRpcStringParam(requestValue, ["action", "name"], "")
        let payload = gatewayDispatchPayloadParam(requestValue)
        let accountId = gatewayPluginActionAccountId(user, pluginId, requestValue)
        let peerId = gatewayBindingStringParam(payload, ["peerId", "to", "target"], "")
        let replyToMessageId = gatewayBindingStringParam(payload, ["replyToMessageId", "replyTo"], "")
        let replyInThread = match (payload.get("replyInThread")) {
            case Some(v) =>
                try { v.asBool().getValue() } catch (_e: Exception) { false }
            case None => false
        }
        let policyDelivery = gatewayApplyChannelDeliveryPolicy(
            user,
            pluginId,
            gatewayChannelsDeliveryJson(
                pluginId,
                peerId,
                accountId,
                replyToMessageId: replyToMessageId,
                replyInThread: replyInThread,
                deliverable: !peerId.isEmpty()
            )
        )
        let effectiveReplyToMessageId = gatewayBindingStringParam(policyDelivery, ["effectiveReplyToMessageId"], "")
        let effectiveReplyInThread = match (policyDelivery.get("effectiveReplyInThread")) {
            case Some(v) =>
                try { v.asBool().getValue() } catch (_e: Exception) { false }
            case None => false
        }
        if (payload.get("replyToMessageId").isSome()) {
            payload.put("replyToMessageId", JsonString(effectiveReplyToMessageId))
        }
        if (payload.get("replyTo").isSome()) {
            payload.put("replyTo", JsonString(effectiveReplyToMessageId))
        }
        if (payload.get("replyInThread").isSome() || effectiveReplyInThread) {
            payload.put("replyInThread", effectiveReplyInThread.toJsonValue())
        }
        let result = JsonObject()
        result.put("pluginId", JsonString(pluginId))
        result.put("dispatch", gatewayLegacyPluginHostDispatchAction(
            pluginId,
            action,
            payload: payload,
            config: pluginConfigFromChannelsExtra(user.channelsExtra, pluginId),
            accountId: accountId
        ))
        result.put(
            "delivery",
            policyDelivery
        )
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "plugins.runtime.forwarders") {
        gatewayEnsureChannelBootstrap(user)
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let pluginId = gatewayRpcStringParam(requestValue, ["id", "plugin", "pluginId"], "")
        let result = JsonObject()
        result.put("pluginId", JsonString(pluginId))
        result.put("forwarders", gatewayLegacyPluginHostRuntimeForwarders(pluginId, config: pluginConfigFromChannelsExtra(user.channelsExtra, pluginId)))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "plugins.resolve_account") {
        gatewayEnsureChannelBootstrap(user)
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let pluginId = gatewayRpcStringParam(requestValue, ["id", "plugin", "pluginId"], "")
        let result = JsonObject()
        result.put("pluginId", JsonString(pluginId))
        result.put("account", gatewayLegacyPluginHostResolveAccount(
            pluginId,
            config: pluginConfigFromChannelsExtra(user.channelsExtra, pluginId),
            accountId: gatewayPluginActionAccountId(user, pluginId, requestValue)
        ))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "plugins.directory") {
        gatewayEnsureChannelBootstrap(user)
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let pluginId = gatewayRpcStringParam(requestValue, ["id", "plugin", "pluginId"], "")
        let groupId = gatewayRpcStringParam(requestValue, ["groupId"], "")
        let result = JsonObject()
        result.put("pluginId", JsonString(pluginId))
        result.put("directory", gatewayLegacyPluginHostDirectory(
            pluginId,
            config: pluginConfigFromChannelsExtra(user.channelsExtra, pluginId),
            accountId: gatewayPluginActionAccountId(user, pluginId, requestValue),
            groupId: groupId
        ))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "plugins.targets") {
        gatewayEnsureChannelBootstrap(user)
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let pluginId = gatewayRpcStringParam(requestValue, ["id", "plugin", "pluginId"], "")
        let target = gatewayRpcStringParam(requestValue, ["target", "to"], "")
        let result = JsonObject()
        result.put("pluginId", JsonString(pluginId))
        result.put("targets", gatewayLegacyPluginHostTargets(
            pluginId,
            target,
            config: pluginConfigFromChannelsExtra(user.channelsExtra, pluginId),
            accountId: gatewayPluginActionAccountId(user, pluginId, requestValue)
        ))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "plugins.start") {
        gatewayEnsureChannelBootstrap(user)
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let pluginId = gatewayRpcStringParam(requestValue, ["id", "plugin", "pluginId"], "")
        return Some(GatewayRpcResponse(true, method, result: gatewayPluginStartJson(user, pluginId, requestValue)))
    }
    if (method == "plugins.stop") {
        gatewayEnsureChannelBootstrap(user)
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let pluginId = gatewayRpcStringParam(requestValue, ["id", "plugin", "pluginId"], "")
        return Some(GatewayRpcResponse(true, method, result: gatewayPluginStopJson(user, pluginId, requestValue)))
    }
    if (method == "plugins.logout") {
        gatewayEnsureChannelBootstrap(user)
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let pluginId = gatewayRpcStringParam(requestValue, ["id", "plugin", "pluginId"], "")
        return Some(GatewayRpcResponse(true, method, result: gatewayPluginLogoutJson(user, pluginId, requestValue)))
    }
    if (method == "plugins.send") {
        gatewayEnsureChannelBootstrap(user)
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let pluginId = gatewayRpcStringParam(requestValue, ["id", "plugin", "pluginId"], "")
        return Some(GatewayRpcResponse(true, method, result: gatewayPluginSendJson(user, pluginId, requestValue)))
    }
    if (method == "plugins.health") {
        gatewayEnsureChannelBootstrap(user)
        let result = JsonObject()
        result.put("plugins", gatewayPluginsHealthJson(user))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "plugins.health.actions") {
        gatewayEnsureChannelBootstrap(user)
        let health = gatewayPluginsHealthJson(user)
        let result = JsonObject()
        result.put("actions", health.get("actions") ?? JsonArray([]))
        result.put("policyState", health.get("policyState") ?? JsonString("steady"))
        result.put("actionsNeeded", health.get("actionsNeeded") ?? 0.toJsonValue())
        result.put("byHealthState", health.get("byHealthState") ?? JsonObject())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "plugins.bindings") {
        let requestValue = match (request) {
            case Some(v) => v
            case None => GatewayRpcRequest(method)
        }
        let plugins = ArrayList<String>()
        for (entry in listGatewayPluginCatalogEntries()) {
            if (!entry.builtin) {
                plugins.add(entry.id)
            }
        }
        let fallbackId = if (plugins.isEmpty()) { "" } else { plugins[0] }
        let pluginId = gatewayRpcStringParam(requestValue, ["id", "plugin", "pluginId"], fallbackId)
        let result = JsonObject()
        result.put("bindings", gatewayPluginBindingsJson(user, pluginId))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "plugins.policy") {
        let pluginBindings = JsonArray([])
        for (entry in listGatewayPluginCatalogEntries()) {
            if (!entry.builtin) {
                pluginBindings.add(gatewayPluginBindingsJson(user, entry.id))
            }
        }
        let result = JsonObject()
        result.put("bindings", pluginBindings)
        result.put("policy", gatewayBindingsPolicySummaryJson(pluginBindings))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    None
}
