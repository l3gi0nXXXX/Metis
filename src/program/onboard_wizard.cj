package metis.program

import metis.core.config.{MetisConfigManager, MetisPaths, CliSettingManager, GatewayPluginUserSettings, GatewayUserSettings,
    cliBaseUrlMatchesAuthChoice, cliFindModelAuthChoice, cliFindModelAuthChoicesForProvider, cliFindModelProviderDescriptor, cliProviderApiKeyConfigPath, cliProviderBaseUrlConfigPath,
    cliModelAuthChoiceGroups, cliSetupVisibleModelProviders, cliValidateProviderBaseUrl}
import metis.gateway.runtime.{gatewayAnotherServeInstanceSeemsRunning, gatewayExecuteRestartServe, gatewayLaunchDedicatedConsole}
import metis.io.{InputUtils, PrintUtils}

import std.collection.ArrayList
import std.fs.exists
import stdx.encoding.json.*

private func wizardEnsureObject(root: JsonObject, key: String): JsonObject {
    match (root.get(key)) {
        case Some(value) =>
            try {
                value.asObject()
            } catch (_e: Exception) {
                let obj = JsonObject()
                root.put(key, obj)
                obj
            }
        case None =>
            let obj = JsonObject()
            root.put(key, obj)
            obj
    }
}

private func wizardReadString(root: JsonObject, key: String): String {
    match (root.get(key)) {
        case Some(value) =>
            try {
                value.asString().getValue()
            } catch (_e: Exception) {
                ""
            }
        case None => ""
    }
}

private func loadOnboardRoot(): JsonObject {
    MetisConfigManager.initializeIfMissing()
    match (MetisConfigManager.rawConfig()) {
        case Some(root) => root
        case None => JsonObject()
    }
}

private func summarizeExistingConfig(root: JsonObject): String {
    let configPath = MetisPaths.configPath().toString()
    let agents = wizardEnsureObject(root, "agents")
    let defaults = wizardEnsureObject(agents, "defaults")
    let workspace = wizardReadString(defaults, "workspace").trimAscii()
    let modelObj = wizardEnsureObject(defaults, "model")
    let model = wizardReadString(modelObj, "primary").trimAscii()
    let gatewayObj = wizardEnsureObject(root, "gateway")
    let skillsObj = wizardEnsureObject(root, "skills")
    let gatewayConfigured = gatewayObj.toJsonString() != "{}"
    let skillsConfigured = skillsObj.toJsonString() != "{}"
    return "Config path: ${configPath}\n" +
        "Workspace: ${if (workspace.isEmpty()) { "(not set)" } else { workspace }}\n" +
        "Primary model: ${if (model.isEmpty()) { "(not set)" } else { model }}\n" +
        "Gateway section: ${if (gatewayConfigured) { "present" } else { "empty" }}\n" +
        "Skills section: ${if (skillsConfigured) { "present" } else { "empty" }}"
}

private func printOnboardHeader(): Unit {
    PrintUtils.printLogo()
    PrintUtils.printLine("")
    PrintUtils.printNoteBox("Metis setup", "Interactive onboarding for gateway, workspace, and skills")
    PrintUtils.printLine("")
}

private func promptRiskAcceptance(): Bool {
    PrintUtils.printNoteBox(
        "Confirm",
        "I understand this is personal-by-default and shared/multi-user use requires lock-down. Continue?"
    )
    match (InputUtils.getOptions(["Continue", "Cancel"])) {
        case Some(index) => index == 0
        case None => false
    }
}

private func promptSetupMode(): String {
    PrintUtils.printLine("")
    PrintUtils.printNoteBox("Setup Mode", "Choose how much configuration to do now.")
    match (InputUtils.getOptions([
        "QuickStart  Configure the main defaults now and finish deeper setup later",
        "Manual      Review setup decisions step by step"
    ])) {
        case Some(index) => if (index == 0) { "quickstart" } else { "manual" }
        case None => "quickstart"
    }
}

private func promptConfigHandling(hasConfig: Bool, root: JsonObject): String {
    PrintUtils.printLine("")
    if (!hasConfig) {
        PrintUtils.printNoteBox(
            "Config Handling",
            "No existing config was detected. A new setup record will be created in ~/.metis/metis.json."
        )
        return "fresh"
    }
    PrintUtils.printNoteBox("Config Handling", "Existing config detected\n\n" + summarizeExistingConfig(root))
    match (InputUtils.getOptions([
        "Keep     Reuse the current config and continue onboarding",
        "Modify   Keep the config but continue with updated onboarding choices",
        "Reset    Keep the file path but mark onboarding as a fresh pass"
    ])) {
        case Some(index) =>
            if (index == 0) {
                "keep"
            } else if (index == 1) {
                "modify"
            } else {
                "reset"
            }
        case None => "keep"
    }
}

private func normalizeWorkspacePath(raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return MetisPaths.workspaceRoot().toString()
    }
    if (trimmed == "~" || trimmed == "~/" || trimmed == "~/.") {
        return MetisPaths.workspaceRoot().toString()
    }
    trimmed
}

func onboardWorkspacePromptState(root: JsonObject): (String, String, String, Bool) {
    let agents = wizardEnsureObject(root, "agents")
    let defaults = wizardEnsureObject(agents, "defaults")
    let currentDirectory = normalizeWorkspacePath(MetisPaths.workspaceRoot().toString())
    let configuredWorkspace = wizardReadString(defaults, "workspace").trimAscii()
    let normalizedConfigured = if (configuredWorkspace.isEmpty()) {
        ""
    } else {
        normalizeWorkspacePath(configuredWorkspace)
    }
    let effectiveWorkspace = if (normalizedConfigured.isEmpty()) {
        currentDirectory
    } else {
        normalizedConfigured
    }
    let showConfiguredOption = !normalizedConfigured.isEmpty() && normalizedConfigured != currentDirectory
    (currentDirectory, normalizedConfigured, effectiveWorkspace, showConfiguredOption)
}

private func promptWorkspaceDirectory(root: JsonObject): String {
    PrintUtils.printLine("")
    let (currentDirectory, configuredWorkspace, defaultWorkspace, showConfiguredOption) = onboardWorkspacePromptState(root)
    let configuredSummary = if (configuredWorkspace.isEmpty()) { "(not set)" } else { configuredWorkspace }
    PrintUtils.printNoteBox(
        "Workspace directory",
        "Choose where Metis should treat as the default workspace.\n\n" +
        "Current directory:\n${currentDirectory}\n\n" +
        "Configured default:\n${configuredSummary}"
    )
    let options = ArrayList<String>()
    options.add("Use current directory  ${currentDirectory}")
    if (showConfiguredOption) {
        options.add("Keep configured default  ${configuredWorkspace}")
    }
    options.add("Enter custom workspace path")
    match (InputUtils.getOptions(options.toArray())) {
        case Some(index) =>
            if (showConfiguredOption && index == 1) {
                return configuredWorkspace
            }
            let customIndex = if (showConfiguredOption) { 2 } else { 1 }
            if (index == customIndex) {
                let input = match (InputUtils.getUserInputOrCancel(prompt: "Workspace directory [default: ${defaultWorkspace}]: ")) {
                    case Some(text) => text.trimAscii()
                    case None => defaultWorkspace
                }
                let next = if (input.isEmpty()) { defaultWorkspace } else { input }
                return normalizeWorkspacePath(next)
            }
            currentDirectory
        case None =>
            currentDirectory
    }
}

private func promptModelProviderId(): String {
    PrintUtils.printLine("")
    let lines = ArrayList<String>()
    for (group in cliModelAuthChoiceGroups()) {
        lines.add("${group.title}: ${group.description}")
    }
    PrintUtils.printNoteBox("Model/auth provider", String.join(lines.toArray(), delimiter: "\n"))
    let providers = cliSetupVisibleModelProviders()
    let options = ArrayList<String>()
    for (provider in providers) {
        let prefix = if (provider.highPriority) { "Recommended" } else { "Optional" }
        options.add("${prefix} | ${provider.displayName} | ${provider.defaultModelRef}")
    }
    options.add("Skip for now")
    match (InputUtils.getOptions(options.toArray())) {
        case Some(index) =>
            if (index >= providers.size) {
                ""
            } else {
                providers[index].providerId
            }
        case None => ""
    }
}

private func promptProviderAuthChoiceId(providerId: String): String {
    let choices = cliFindModelAuthChoicesForProvider(providerId)
    if (choices.isEmpty()) {
        return ""
    }
    if (choices.size == 1) {
        return choices[0].choiceId
    }
    PrintUtils.printLine("")
    match (cliFindModelProviderDescriptor(providerId)) {
        case Some(provider) =>
            PrintUtils.printNoteBox(
                "${provider.displayName} auth method",
                "Choose how Metis should authenticate to ${provider.displayName}."
            )
        case None => ()
    }
    let options = ArrayList<String>()
    for (choice in choices) {
        options.add("${choice.label} (${choice.description})")
    }
    options.add("Back")
    match (InputUtils.getOptions(options.toArray())) {
        case Some(index) =>
            if (index >= choices.size) {
                "__back__"
            } else {
                choices[index].choiceId
            }
        case None => "__back__"
    }
}

private func promptProviderCredentials(choiceId: String, providerId: String): (String, String) {
    let currentApiKey = MetisConfigManager.readProviderApiKey(providerId).trimAscii()
    let currentBaseUrl = MetisConfigManager.readProviderBaseUrl(providerId).trimAscii()
    match (cliFindModelAuthChoice(choiceId)) {
        case Some(choice) =>
            let provider = match (cliFindModelProviderDescriptor(providerId)) {
                case Some(value) => value
                case None => return ("", "")
            }
            PrintUtils.printLine("")
            PrintUtils.printNoteBox(
                "${provider.displayName} auth method",
                "${choice.label}\n${choice.description}\n\nProvider: ${provider.displayName}\nAPI key config: ${cliProviderApiKeyConfigPath(provider.providerId)}\nBase URL config: ${cliProviderBaseUrlConfigPath(provider.providerId)}"
            )
            let apiKeyConfigPath = cliProviderApiKeyConfigPath(provider.providerId)
            let apiKey = if (apiKeyConfigPath.trimAscii().isEmpty()) {
                currentApiKey
            } else {
                let apiKeyPrompt = if (currentApiKey.isEmpty()) {
                    "API key [optional, stored at ${apiKeyConfigPath}, Enter to skip for now]: "
                } else {
                    "API key [default: keep current at ${apiKeyConfigPath}]: "
                }
                match (InputUtils.getUserInputOrCancel(prompt: apiKeyPrompt)) {
                    case Some(text) =>
                        let trimmed = text.trimAscii()
                        if (trimmed.isEmpty()) { currentApiKey } else { trimmed }
                    case None => currentApiKey
                }
            }
            let suggestedBaseUrl = if (!choice.baseUrl.trimAscii().isEmpty()) { choice.baseUrl } else { provider.defaultBaseUrl }
            let defaultBaseUrl = if (currentBaseUrl.isEmpty() || !cliBaseUrlMatchesAuthChoice(choiceId, currentBaseUrl)) {
                suggestedBaseUrl
            } else {
                currentBaseUrl
            }
            var finalBaseUrl = defaultBaseUrl
            while (true) {
                let baseUrlPrompt = "Base URL [default: ${defaultBaseUrl}, stored at ${cliProviderBaseUrlConfigPath(provider.providerId)}]: "
                let baseUrl = match (InputUtils.getUserInputOrCancel(prompt: baseUrlPrompt)) {
                    case Some(text) =>
                        let trimmed = text.trimAscii()
                        if (trimmed.isEmpty()) { defaultBaseUrl } else { trimmed }
                    case None => defaultBaseUrl
                }
                let validation = cliValidateProviderBaseUrl(providerId, baseUrl)
                if (validation.trimAscii().isEmpty()) {
                    finalBaseUrl = baseUrl
                    break
                }
                PrintUtils.printLine("")
                PrintUtils.printNoteBox("${provider.displayName} base URL", validation)
            }
            (apiKey, finalBaseUrl)
        case None => ("", "")
    }
}

private func normalizeModelRefForProvider(providerId: String, raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return ""
    }
    if (trimmed.contains(":") || trimmed.contains("/")) {
        return MetisConfigManager.canonicalModelRef(trimmed)
    }
    MetisConfigManager.canonicalModelRef("${providerId}:${trimmed}")
}

private func configModelRefForStorage(modelRef: String): String {
    let canonical = MetisConfigManager.canonicalModelRef(modelRef).trimAscii()
    if (canonical.contains(":")) {
        let parts = canonical.split(":")
        if (parts.size >= 2) {
            return "${parts[0]}/${String.join(parts[1..parts.size], delimiter: ":")}"
        }
    }
    canonical
}

private func promptDefaultModelRef(providerId: String, defaultModelRef: String): String {
    PrintUtils.printLine("")
    PrintUtils.printNoteBox(
        "Default model",
        "Choose the default model for the selected provider.\n\nRecommended default:\n${defaultModelRef}"
    )
    let currentModel = MetisConfigManager.canonicalModelRef(MetisConfigManager.readPrimaryModel() ?? "").trimAscii()
    let options = ArrayList<String>()
    options.add("Use recommended default  ${defaultModelRef}")
    if (!currentModel.isEmpty()) {
        options.add("Keep current model  ${currentModel}")
    }
    options.add("Enter custom model id")
    match (InputUtils.getOptions(options.toArray())) {
        case Some(index) =>
            if (index == 0) {
                return defaultModelRef
            }
            if (!currentModel.isEmpty() && index == 1) {
                return currentModel
            }
            let input = match (InputUtils.getUserInputOrCancel(prompt: "Model ref [default: ${defaultModelRef}]: ")) {
                case Some(text) => text.trimAscii()
                case None => defaultModelRef
            }
            let resolved = normalizeModelRefForProvider(providerId, if (input.isEmpty()) { defaultModelRef } else { input })
            if (resolved.isEmpty()) { defaultModelRef } else { resolved }
        case None => defaultModelRef
    }
}

private func promptGatewayStage(): String {
    PrintUtils.printLine("")
    PrintUtils.printNoteBox(
        "Gateway",
        "Configure gateway exposure, bind, auth, and runtime defaults.\n\nThis stage is not fully wired yet in Metis. Keep defaults for now and continue onboarding."
    )
    match (InputUtils.getOptions([
        "Keep current/default gateway settings",
        "Review later from configure/gateway commands"
    ])) {
        case Some(1) => "later"
        case _ => "keep"
    }
}

private func promptChannelQuickStart(): String {
    PrintUtils.printLine("")
    PrintUtils.printNoteBox(
        "Select channel (QuickStart)",
        "Choose a channel to continue configuring during onboarding.\n\n" +
        "This first pass wires the channel stage into onboarding. Detailed per-channel fields will continue in later steps."
    )
    match (InputUtils.getOptions([
        "Feishu/Lark (飞书)",
        "QQ Bot",
        "Telegram (Bot API)",
        "Slack",
        "Discord (Bot API)",
        "DingTalk (plugin)",
        "metis-weixin (plugin)",
        "Webhook / Web channel",
        "Skip for now"
    ])) {
        case Some(0) => "feishu"
        case Some(1) => "qq"
        case Some(2) => "telegram"
        case Some(3) => "slack"
        case Some(4) => "discord"
        case Some(5) => "dingtalk"
        case Some(6) => "metis-weixin"
        case Some(7) => "webhook"
        case _ => "skip"
    }
}

private func promptOptionalInput(prompt: String, current: String): String {
    match (InputUtils.getUserInputOrCancel(prompt: prompt)) {
        case Some(text) =>
            let trimmed = text.trimAscii()
            if (trimmed.isEmpty()) { current } else { trimmed }
        case None => current
    }
}

private func channelExtraObject(user: GatewayUserSettings, channelId: String): JsonObject {
    let normalized = channelId.trimAscii().toAsciiLower()
    match (user.channelsExtra) {
        case Some(extra) =>
            match (extra.get(normalized)) {
                case Some(value) =>
                    try {
                        value.asObject()
                    } catch (_: Exception) {
                        JsonObject()
                    }
                case None => JsonObject()
            }
        case None => JsonObject()
    }
}

private func channelPersistExtraObject(user: GatewayUserSettings, channelId: String, config: JsonObject): GatewayUserSettings {
    let normalized = channelId.trimAscii().toAsciiLower()
    var updated = user
    let root = match (updated.channelsExtra) {
        case Some(extra) => extra
        case None => JsonObject()
    }
    root.put(normalized, config)
    updated.channelsExtra = Some(root)
    updated
}

private func persistGatewaySettings(user: GatewayUserSettings): Unit {
    CliSettingManager.writeGatewaySettings(user)
    MetisConfigManager.applyPersistedFieldsToCliConfig()
}

private func ensureGatewayPluginEnabled(user: GatewayUserSettings, pluginId: String): GatewayUserSettings {
    let normalized = pluginId.trimAscii().toAsciiLower()
    var updated = user
    var found = false
    let next = ArrayList<GatewayPluginUserSettings>()
    for (plugin in updated.gatewayPlugins) {
        if (plugin.id.trimAscii().toAsciiLower() == normalized) {
            next.add(GatewayPluginUserSettings(id: normalized, enabled: true))
            found = true
        } else {
            next.add(plugin)
        }
    }
    if (!found) {
        next.add(GatewayPluginUserSettings(id: normalized, enabled: true))
    }
    updated.gatewayPlugins = next.toArray()
    updated
}

private func promptFeishuQuickStart(user: GatewayUserSettings): Unit {
    PrintUtils.printLine("")
    PrintUtils.printNoteBox(
        "Feishu/Lark setup",
        "Configure the built-in Feishu/Lark channel.\n\n" +
        "Required now:\n- App ID\n- App Secret\n- Receive mode"
    )
    var updated = user
    updated.feishu.enabled = true
    updated.feishu.appId = promptOptionalInput(
        "gateway.feishu.appId [current: ${updated.feishu.appId}]: ",
        updated.feishu.appId
    )
    updated.feishu.appSecret = promptOptionalInput(
        "gateway.feishu.appSecret [current: ${if (updated.feishu.appSecret.isEmpty()) { "(empty)" } else { "keep current" }}]: ",
        updated.feishu.appSecret
    )
    match (InputUtils.getOptions([
        "Long connect (recommended)",
        "Webhook"
    ], prompt: "Feishu receive mode")) {
        case Some(1) => updated.feishu.receiveMode = "webhook"
        case _ => updated.feishu.receiveMode = "long_connect"
    }
    match (InputUtils.getOptions([
        "Feishu (China, open.feishu.cn)",
        "Lark (International, open.larksuite.com)"
    ], prompt: "Feishu domain")) {
        case Some(1) => updated.feishu.domain = "https://open.larksuite.com"
        case _ => updated.feishu.domain = "https://open.feishu.cn"
    }
    match (InputUtils.getOptions([
        "group（一个群一条会话）",
        "group_sender（群内按发送者隔离）",
        "group_topic（按话题线程隔离）",
        "group_topic_sender（按话题 + 发送者隔离）"
    ], prompt: "Feishu group session scope")) {
        case Some(1) => updated.feishu.groupSessionScope = "group_sender"
        case Some(2) => updated.feishu.groupSessionScope = "group_topic"
        case Some(3) => updated.feishu.groupSessionScope = "group_topic_sender"
        case _ => updated.feishu.groupSessionScope = "group"
    }
    match (InputUtils.getOptions([
        "Disabled（普通回复）",
        "Enabled（群聊回复走话题线程）"
    ], prompt: "Feishu reply in thread")) {
        case Some(1) => updated.feishu.replyInThread = "enabled"
        case _ => updated.feishu.replyInThread = "disabled"
    }
    if (updated.feishu.receiveMode == "webhook") {
        updated.feishu.verificationToken = promptOptionalInput(
            "gateway.feishu.verificationToken [current: ${if (updated.feishu.verificationToken.isEmpty()) { "(empty)" } else { "keep current" }}]: ",
            updated.feishu.verificationToken
        )
        updated.feishu.encryptKey = promptOptionalInput(
            "gateway.feishu.encryptKey [current: ${if (updated.feishu.encryptKey.isEmpty()) { "(empty)" } else { "keep current" }}]: ",
            updated.feishu.encryptKey
        )
    }
    persistGatewaySettings(updated)
}

private func promptQqQuickStart(user: GatewayUserSettings): Unit {
    PrintUtils.printLine("")
    PrintUtils.printNoteBox(
        "QQ Bot setup",
        "Configure the built-in QQ Bot channel.\n\n" +
        "This setup uses the official QQ Bot API via the WebSocket gateway.\n\n" +
        "Supported in the current runtime:\n- official_ws mode\n- private chat receive/send\n- group mention receive/send\n\n" +
        "Not part of the supported setup path yet:\n- webhook mode\n- OneBot gateway\n\n" +
        "Required now:\n- gateway.qq.appId\n- gateway.qq.appSecret"
    )
    var updated = user
    updated.qq.enabled = true
    updated.qq.mode = "official_ws"
    updated.qq.appId = promptOptionalInput(
        "gateway.qq.appId [current: ${updated.qq.appId}]: ",
        updated.qq.appId
    )
    updated.qq.appSecret = promptOptionalInput(
        "gateway.qq.appSecret [current: ${if (updated.qq.appSecret.isEmpty()) { "(empty)" } else { "keep current" }}]: ",
        updated.qq.appSecret
    )
    persistGatewaySettings(updated)
}

private func promptTelegramQuickStart(user: GatewayUserSettings): Unit {
    PrintUtils.printLine("")
    PrintUtils.printNoteBox(
        "Telegram setup",
        "Configure the built-in Telegram Bot API channel."
    )
    let token = promptOptionalInput(
        "gateway.telegram.botToken [current: ${if (user.telegram.botToken.trimAscii().isEmpty()) { "(empty)" } else { "keep current" }}]: ",
        user.telegram.botToken.trimAscii()
    )
    var updated = user
    updated.telegram.enabled = true
    updated.telegram.botToken = token.trimAscii()
    persistGatewaySettings(updated)
}

private func promptSlackQuickStart(user: GatewayUserSettings): Unit {
    PrintUtils.printLine("")
    PrintUtils.printNoteBox(
        "Slack setup",
        "Configure the built-in Slack channel.\n\nBot token is required for most setups. App token is optional."
    )
    let current = channelExtraObject(user, "slack")
    let botTokenCurrent = match (current.get("botToken")) {
        case Some(value) =>
            try { value.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
    let appTokenCurrent = match (current.get("appToken")) {
        case Some(value) =>
            try { value.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
    let botToken = promptOptionalInput(
        "SLACK_BOT_TOKEN [current: ${if (botTokenCurrent.isEmpty()) { "(empty)" } else { "keep current" }}]: ",
        botTokenCurrent
    )
    let appToken = promptOptionalInput(
        "SLACK_APP_TOKEN [current: ${if (appTokenCurrent.isEmpty()) { "(empty)" } else { "keep current" }}]: ",
        appTokenCurrent
    )
    let updatedCfg = JsonObject()
    updatedCfg.put("enabled", JsonBool(true))
    updatedCfg.put("configured", JsonBool(!botToken.isEmpty()))
    updatedCfg.put("botToken", JsonString(botToken))
    if (!appToken.isEmpty()) {
        updatedCfg.put("appToken", JsonString(appToken))
    }
    persistGatewaySettings(channelPersistExtraObject(user, "slack", updatedCfg))
}

private func promptDiscordQuickStart(user: GatewayUserSettings): Unit {
    PrintUtils.printLine("")
    PrintUtils.printNoteBox(
        "Discord setup",
        "Configure the built-in Discord Bot API channel."
    )
    let current = channelExtraObject(user, "discord")
    let botTokenCurrent = match (current.get("botToken")) {
        case Some(value) =>
            try { value.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
    let guildIdCurrent = match (current.get("guildId")) {
        case Some(value) =>
            try { value.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
    let botToken = promptOptionalInput(
        "DISCORD_BOT_TOKEN [current: ${if (botTokenCurrent.isEmpty()) { "(empty)" } else { "keep current" }}]: ",
        botTokenCurrent
    )
    let guildId = promptOptionalInput(
        "DISCORD_GUILD_ID [current: ${if (guildIdCurrent.isEmpty()) { "(optional)" } else { guildIdCurrent }}]: ",
        guildIdCurrent
    )
    let updatedCfg = JsonObject()
    updatedCfg.put("enabled", JsonBool(true))
    updatedCfg.put("configured", JsonBool(!botToken.isEmpty()))
    updatedCfg.put("botToken", JsonString(botToken))
    if (!guildId.isEmpty()) {
        updatedCfg.put("guildId", JsonString(guildId))
    }
    persistGatewaySettings(channelPersistExtraObject(user, "discord", updatedCfg))
}

private func promptDingTalkQuickStart(user: GatewayUserSettings): Unit {
    PrintUtils.printLine("")
    PrintUtils.printNoteBox(
        "DingTalk setup",
        "Configure the DingTalk plugin channel.\n\nThis onboarding pass stores plugin settings and enables the gateway plugin entry."
    )
    let current = channelExtraObject(user, "dingtalk")
    let appKeyCurrent = match (current.get("appKey")) {
        case Some(value) =>
            try { value.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
    let appSecretCurrent = match (current.get("appSecret")) {
        case Some(value) =>
            try { value.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
    let webhookUrlCurrent = match (current.get("webhookUrl")) {
        case Some(value) =>
            try { value.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
    let appKey = promptOptionalInput("DINGTALK_APP_KEY [current: ${if (appKeyCurrent.isEmpty()) { "(empty)" } else { appKeyCurrent }}]: ", appKeyCurrent)
    let appSecret = promptOptionalInput("DINGTALK_APP_SECRET [current: ${if (appSecretCurrent.isEmpty()) { "(empty)" } else { "keep current" }}]: ", appSecretCurrent)
    let webhookUrl = promptOptionalInput("DINGTALK_WEBHOOK_URL [current: ${if (webhookUrlCurrent.isEmpty()) { "(optional)" } else { webhookUrlCurrent }}]: ", webhookUrlCurrent)
    let updatedCfg = JsonObject()
    updatedCfg.put("enabled", JsonBool(true))
    updatedCfg.put("configured", JsonBool(!(appKey.isEmpty() && appSecret.isEmpty() && webhookUrl.isEmpty())))
    if (!appKey.isEmpty()) { updatedCfg.put("appKey", JsonString(appKey)) }
    if (!appSecret.isEmpty()) { updatedCfg.put("appSecret", JsonString(appSecret)) }
    if (!webhookUrl.isEmpty()) { updatedCfg.put("webhookUrl", JsonString(webhookUrl)) }
    var updated = ensureGatewayPluginEnabled(user, "dingtalk")
    updated = channelPersistExtraObject(updated, "dingtalk", updatedCfg)
    persistGatewaySettings(updated)
}

private func promptWeixinQuickStart(user: GatewayUserSettings): Unit {
    PrintUtils.printLine("")
    PrintUtils.printNoteBox(
        "Weixin plugin setup",
        "Configure the Weixin plugin channel.\n\nThis onboarding pass stores bridge settings and enables the plugin entry."
    )
    let current = channelExtraObject(user, "metis-weixin")
    let modeCurrent = match (current.get("mode")) {
        case Some(value) =>
            try { value.asString().getValue().trimAscii() } catch (_: Exception) { "long-poll" }
        case None => "long-poll"
    }
    let bridgeUrlCurrent = match (current.get("bridgeUrl")) {
        case Some(value) =>
            try { value.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
    let authTokenCurrent = match (current.get("authToken")) {
        case Some(value) =>
            try { value.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
    let mode = match (InputUtils.getOptions([
        "Long-poll (recommended)",
        "Webhook / bridge"
    ], prompt: "Weixin mode")) {
        case Some(1) => "webhook"
        case _ => "long-poll"
    }
    let bridgeUrl = promptOptionalInput("WEIXIN_BRIDGE_URL [current: ${if (bridgeUrlCurrent.isEmpty()) { "(optional)" } else { bridgeUrlCurrent }}]: ", bridgeUrlCurrent)
    let authToken = promptOptionalInput("WEIXIN_AUTH_TOKEN [current: ${if (authTokenCurrent.isEmpty()) { "(optional)" } else { "keep current" }}]: ", authTokenCurrent)
    let updatedCfg = JsonObject()
    updatedCfg.put("enabled", JsonBool(true))
    updatedCfg.put("configured", JsonBool(!(bridgeUrl.isEmpty() && authToken.isEmpty())))
    updatedCfg.put("mode", JsonString(mode))
    if (!bridgeUrl.isEmpty()) { updatedCfg.put("bridgeUrl", JsonString(bridgeUrl)) }
    if (!authToken.isEmpty()) { updatedCfg.put("authToken", JsonString(authToken)) }
    var updated = ensureGatewayPluginEnabled(user, "metis-weixin")
    updated = channelPersistExtraObject(updated, "metis-weixin", updatedCfg)
    persistGatewaySettings(updated)
}

private func promptWebhookQuickStart(user: GatewayUserSettings): Unit {
    PrintUtils.printLine("")
    PrintUtils.printNoteBox(
        "Webhook / Web channel setup",
        "Configure a generic webhook/web channel surface.\n\nThis stores a gateway plugin-style config entry for later runtime wiring."
    )
    let current = channelExtraObject(user, "webhook")
    let webhookUrlCurrent = match (current.get("webhookUrl")) {
        case Some(value) =>
            try { value.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
    let authTokenCurrent = match (current.get("authToken")) {
        case Some(value) =>
            try { value.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
    let webhookUrl = promptOptionalInput("WEBHOOK_URL [current: ${if (webhookUrlCurrent.isEmpty()) { "(empty)" } else { webhookUrlCurrent }}]: ", webhookUrlCurrent)
    let authToken = promptOptionalInput("WEBHOOK_AUTH_TOKEN [current: ${if (authTokenCurrent.isEmpty()) { "(optional)" } else { "keep current" }}]: ", authTokenCurrent)
    let updatedCfg = JsonObject()
    updatedCfg.put("enabled", JsonBool(true))
    updatedCfg.put("configured", JsonBool(!webhookUrl.isEmpty()))
    if (!webhookUrl.isEmpty()) { updatedCfg.put("webhookUrl", JsonString(webhookUrl)) }
    if (!authToken.isEmpty()) { updatedCfg.put("authToken", JsonString(authToken)) }
    var updated = ensureGatewayPluginEnabled(user, "webhook")
    updated = channelPersistExtraObject(updated, "webhook", updatedCfg)
    persistGatewaySettings(updated)
}

private func runChannelQuickStart(channelId: String): Unit {
    let normalized = channelId.trimAscii().toAsciiLower()
    if (normalized.isEmpty() || normalized == "skip") {
        return
    }
    let user = CliSettingManager.readGatewaySettings()
    match (normalized) {
        case "feishu" => promptFeishuQuickStart(user)
        case "qq" => promptQqQuickStart(user)
        case "telegram" => promptTelegramQuickStart(user)
        case "slack" => promptSlackQuickStart(user)
        case "discord" => promptDiscordQuickStart(user)
        case "dingtalk" => promptDingTalkQuickStart(user)
        case "metis-weixin" => promptWeixinQuickStart(user)
        case "webhook" => promptWebhookQuickStart(user)
        case _ => ()
    }
}

private func channelSummaryLine(channelId: String): String {
    let normalized = channelId.trimAscii().toAsciiLower()
    if (normalized.isEmpty() || normalized == "skip") {
        return "Skipped for now"
    }
    let user = CliSettingManager.readGatewaySettings()
    match (normalized) {
        case "feishu" =>
            let configured = !user.feishu.appId.trimAscii().isEmpty()
            "feishu | enabled=${user.feishu.enabled} | configured=${configured} | mode=${user.feishu.receiveMode}"
        case "qq" =>
            let configured = !(user.qq.appId.trimAscii().isEmpty() || user.qq.appSecret.trimAscii().isEmpty())
            "qq | enabled=${user.qq.enabled} | configured=${configured} | mode=${user.qq.mode}"
        case "telegram" =>
            let configured = !user.telegram.botToken.trimAscii().isEmpty() ||
                !user.telegram.tokenFile.trimAscii().isEmpty() ||
                !user.telegram.webhookUrl.trimAscii().isEmpty()
            "telegram | enabled=${user.telegram.enabled} | configured=${configured} | mode=${if (!user.telegram.webhookUrl.trimAscii().isEmpty()) { "webhook" } else { "polling" }}"
        case "slack" =>
            let cfg = channelExtraObject(user, "slack")
            let configured = match (cfg.get("configured")) {
                case Some(value) =>
                    try { value.asBool().getValue() } catch (_: Exception) { false }
                case None => false
            }
            "slack | enabled=true | configured=${configured}"
        case "discord" =>
            let cfg = channelExtraObject(user, "discord")
            let configured = match (cfg.get("configured")) {
                case Some(value) =>
                    try { value.asBool().getValue() } catch (_: Exception) { false }
                case None => false
            }
            "discord | enabled=true | configured=${configured}"
        case "dingtalk" =>
            let cfg = channelExtraObject(user, "dingtalk")
            let configured = match (cfg.get("configured")) {
                case Some(value) =>
                    try { value.asBool().getValue() } catch (_: Exception) { false }
                case None => false
            }
            "dingtalk | plugin=true | configured=${configured}"
        case "metis-weixin" =>
            let cfg = channelExtraObject(user, "metis-weixin")
            let configured = match (cfg.get("configured")) {
                case Some(value) =>
                    try { value.asBool().getValue() } catch (_: Exception) { false }
                case None => false
            }
            let mode = match (cfg.get("mode")) {
                case Some(value) =>
                    try { value.asString().getValue().trimAscii() } catch (_: Exception) { "long-poll" }
                case None => "long-poll"
            }
            "metis-weixin | plugin=true | configured=${configured} | mode=${mode}"
        case "webhook" =>
            let cfg = channelExtraObject(user, "webhook")
            let configured = match (cfg.get("configured")) {
                case Some(value) =>
                    try { value.asBool().getValue() } catch (_: Exception) { false }
                case None => false
            }
            "webhook | plugin=true | configured=${configured}"
        case _ => normalized
    }
}

private func promptSearchStage(): String {
    PrintUtils.printLine("")
    PrintUtils.printNoteBox(
        "Search",
        "Configure web search provider and credentials.\n\nSearch setup is staged but not fully interactive yet."
    )
    match (InputUtils.getOptions([
        "Skip for now",
        "Review later from configure"
    ])) {
        case Some(1) => "later"
        case _ => "skip"
    }
}

private func promptSkillsStage(): String {
    PrintUtils.printLine("")
    PrintUtils.printNoteBox(
        "Skills",
        "Choose whether to keep built-in skills enabled during onboarding.\n\nSkill-specific onboarding remains separate."
    )
    match (InputUtils.getOptions([
        "Keep default skills configuration",
        "Review later from configure"
    ])) {
        case Some(1) => "later"
        case _ => "keep"
    }
}

private func printFinalizeStage(workspace: String, providerId: String, modelRef: String, channelId: String): Unit {
    PrintUtils.printLine("")
    let providerSummary = if (providerId.trimAscii().isEmpty()) { "Skipped for now" } else { providerId }
    let modelSummary = if (modelRef.trimAscii().isEmpty()) { "Skipped for now" } else { configModelRefForStorage(modelRef) }
    let channelSummary = channelSummaryLine(channelId)
    PrintUtils.printNoteBox(
        "Finalize",
        "Onboarding selections saved.\n\nWorkspace: ${workspace}\nModel/auth provider: ${providerSummary}\nDefault model: ${modelSummary}\nChannel: ${channelSummary}\n\nContinue later with:\n- metis configure\n- metis models providers\n- metis gateway channel list"
    )
}

private func promptGatewayServiceRuntime(): String {
    PrintUtils.printLine("")
    PrintUtils.printNoteBox(
        "Gateway service runtime",
        "QuickStart uses the local gateway service runtime for channels.\n\n" +
        "Channel configuration only takes effect after the gateway service is started or restarted."
    )
    if (gatewayAnotherServeInstanceSeemsRunning()) {
        match (InputUtils.getOptions([
            "Restart",
            "Reinstall",
            "Skip"
        ], prompt: "Gateway service already installed")) {
            case Some(0) => "restart"
            case Some(1) => "reinstall"
            case _ => "skip"
        }
    } else {
        match (InputUtils.getOptions([
            "Install Gateway service (recommended)",
            "Skip"
        ], prompt: "Gateway service")) {
            case Some(0) => "install"
            case _ => "skip"
        }
    }
}

private func applyGatewayServiceRuntimeSelection(selection: String): Unit {
    match (selection.trimAscii().toAsciiLower()) {
        case "restart" =>
            let code = gatewayExecuteRestartServe()
            if (code == 0) {
                PrintUtils.printLine("Gateway service restarted.")
            } else {
                PrintUtils.printLine("Gateway service restart failed.")
            }
        case "reinstall" =>
            let code = gatewayExecuteRestartServe()
            if (code == 0) {
                PrintUtils.printLine("Gateway service reinstalled.")
            } else {
                PrintUtils.printLine("Gateway service reinstall failed.")
            }
        case "install" =>
            if (gatewayLaunchDedicatedConsole()) {
                PrintUtils.printLine("Gateway service installed.")
            } else {
                PrintUtils.printLine("Gateway service install failed.")
            }
        case _ => ()
    }
}

private func persistModelSelections(workspace: String, choiceId: String, providerId: String, apiKey: String, baseUrl: String, modelRef: String): Unit {
    let root = loadOnboardRoot()
    let agents = wizardEnsureObject(root, "agents")
    let defaults = wizardEnsureObject(agents, "defaults")
    defaults.put("workspace", JsonString(workspace))
    let model = wizardEnsureObject(defaults, "model")
    model.put("primary", JsonString(configModelRefForStorage(modelRef)))

    let models = wizardEnsureObject(root, "models")
    let providers = wizardEnsureObject(models, "providers")
    let provider = wizardEnsureObject(providers, providerId)
    if (!apiKey.trimAscii().isEmpty()) {
        provider.put("apiKey", JsonString(apiKey.trimAscii()))
    }
    if (!baseUrl.trimAscii().isEmpty()) {
        provider.put("baseUrl", JsonString(baseUrl.trimAscii()))
    }

    let auth = wizardEnsureObject(root, "auth")
    let profiles = wizardEnsureObject(auth, "profiles")
    let profileId = "${providerId}:default"
    let profile = wizardEnsureObject(profiles, profileId)
    profile.put("provider", JsonString(providerId))
    profile.put("authMethod", JsonString("api-key"))
    if (!apiKey.trimAscii().isEmpty()) {
        profile.put("apiKey", JsonString(apiKey.trimAscii()))
    }
    if (!baseUrl.trimAscii().isEmpty()) {
        profile.put("baseUrl", JsonString(baseUrl.trimAscii()))
    }
    profile.put("modelRef", JsonString(configModelRefForStorage(modelRef)))

    let wizard = wizardEnsureObject(root, "wizard")
    let onboard = wizardEnsureObject(wizard, "onboard")
    onboard.put("modelProviderChoice", JsonString(choiceId))
    onboard.put("modelProvider", JsonString(providerId))
    onboard.put("defaultModelRef", JsonString(configModelRefForStorage(modelRef)))
    onboard.put("workspace", JsonString(workspace))

    let meta = wizardEnsureObject(root, "meta")
    let cj = wizardEnsureObject(meta, "metis")
    let wizardMeta = wizardEnsureObject(cj, "wizard")
    wizardMeta.put("lastModelProviderChoice", JsonString(choiceId))
    wizardMeta.put("lastModelProvider", JsonString(providerId))
    wizardMeta.put("lastModelRef", JsonString(configModelRefForStorage(modelRef)))
    wizardMeta.put("lastWorkspace", JsonString(workspace))

    MetisConfigManager.writeRoot(root)
    MetisConfigManager.applyPersistedFieldsToCliConfig()
}

private func persistOnboardSelections(mode: String, configHandling: String, gatewayStage: String, channelQuickStart: String, searchStage: String, skillsStage: String, gatewayServiceRuntime: String): Unit {
    let root = loadOnboardRoot()
    let wizard = wizardEnsureObject(root, "wizard")
    let onboard = wizardEnsureObject(wizard, "onboard")
    onboard.put("riskAccepted", JsonBool(true))
    onboard.put("setupMode", JsonString(mode))
    onboard.put("configHandling", JsonString(configHandling))
    onboard.put("gatewayStage", JsonString(gatewayStage))
    onboard.put("channelQuickStart", JsonString(channelQuickStart))
    onboard.put("channelSummary", JsonString(channelSummaryLine(channelQuickStart)))
    onboard.put("searchStage", JsonString(searchStage))
    onboard.put("skillsStage", JsonString(skillsStage))
    onboard.put("gatewayServiceRuntime", JsonString(gatewayServiceRuntime))

    let meta = wizardEnsureObject(root, "meta")
    let cj = wizardEnsureObject(meta, "metis")
    let wizardMeta = wizardEnsureObject(cj, "wizard")
    wizardMeta.put("lastMode", JsonString(mode))
    wizardMeta.put("lastConfigHandling", JsonString(configHandling))
    wizardMeta.put("lastGatewayStage", JsonString(gatewayStage))
    wizardMeta.put("lastChannelQuickStart", JsonString(channelQuickStart))
    wizardMeta.put("lastChannelSummary", JsonString(channelSummaryLine(channelQuickStart)))
    wizardMeta.put("lastSearchStage", JsonString(searchStage))
    wizardMeta.put("lastSkillsStage", JsonString(skillsStage))
    wizardMeta.put("lastGatewayServiceRuntime", JsonString(gatewayServiceRuntime))
    wizardMeta.put("homeRoot", JsonString(MetisPaths.homeRoot().toString()))

    MetisConfigManager.writeRoot(root)
}

private func resolveModelProviderSelection(): (String, String) {
    while (true) {
        let providerId = promptModelProviderId()
        if (providerId.isEmpty()) {
            return ("", "")
        }
        let choiceId = promptProviderAuthChoiceId(providerId)
        if (choiceId == "__back__") {
            continue
        }
        return (providerId, choiceId)
    }
    ("", "")
}

public func runConfigureModelWizard(): Int64 {
    let root = loadOnboardRoot()
    let workspace = promptWorkspaceDirectory(root)
    let (providerId, choiceId) = resolveModelProviderSelection()
    if (providerId.isEmpty() || choiceId.isEmpty()) {
        PrintUtils.printLine("Configuration cancelled.")
        return CLI_EXIT_USAGE_ERROR
    }
    let choice = match (cliFindModelAuthChoice(choiceId)) {
        case Some(value) => value
        case None =>
            PrintUtils.printLine("Configuration cancelled.")
            return CLI_EXIT_USAGE_ERROR
    }
    let (apiKey, baseUrl) = promptProviderCredentials(choice.choiceId, providerId)
    let modelRef = promptDefaultModelRef(providerId, choice.defaultModelRef)
    persistModelSelections(workspace, choice.choiceId, providerId, apiKey, baseUrl, modelRef)
    PrintUtils.printLine("")
    PrintUtils.printLine("Model configuration saved.")
    PrintUtils.printLine("Workspace: ${workspace}")
    PrintUtils.printLine("Provider: ${providerId}")
    PrintUtils.printLine("Model: ${configModelRefForStorage(modelRef)}")
    PrintUtils.printLine("")
    cliReturnOk()
}

public func runOnboardWizard(): Int64 {
    let path = MetisPaths.configPath()
    let hasConfig = exists(path)
    let root = loadOnboardRoot()

    printOnboardHeader()
    if (!promptRiskAcceptance()) {
        PrintUtils.printLine("Onboarding cancelled.")
        return CLI_EXIT_USAGE_ERROR
    }

    let setupMode = promptSetupMode()
    let configHandling = promptConfigHandling(hasConfig, root)
    let workspace = promptWorkspaceDirectory(root)
    let (providerId, choiceId) = resolveModelProviderSelection()
    var modelRef = ""
    if (!providerId.isEmpty() && !choiceId.isEmpty()) {
        match (cliFindModelAuthChoice(choiceId)) {
            case Some(choice) =>
                let (apiKey, baseUrl) = promptProviderCredentials(choice.choiceId, providerId)
                modelRef = promptDefaultModelRef(providerId, choice.defaultModelRef)
                persistModelSelections(workspace, choice.choiceId, providerId, apiKey, baseUrl, modelRef)
            case None => ()
        }
    }

    let gatewayStage = promptGatewayStage()
    let channelQuickStart = promptChannelQuickStart()
    runChannelQuickStart(channelQuickStart)
    let searchStage = promptSearchStage()
    let skillsStage = promptSkillsStage()
    let gatewayServiceRuntime = promptGatewayServiceRuntime()
    applyGatewayServiceRuntimeSelection(gatewayServiceRuntime)
    persistOnboardSelections(setupMode, configHandling, gatewayStage, channelQuickStart, searchStage, skillsStage, gatewayServiceRuntime)
    printFinalizeStage(workspace, providerId, modelRef, channelQuickStart)
    cliReturnOk()
}
