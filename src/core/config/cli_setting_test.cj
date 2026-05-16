package metis.core.config

import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject, JsonString}

@Test
public class CliSettingManagerTest {
    @TestCase
    public func explicitTopLevelEmptyMemoryBackendDoesNotReviveLegacyProvider(): Unit {
        var setting = CliSetting()
        setting.memory.backend = ""
        setting.memoryProvider = "qmd"
        let root = JsonObject()
        let memory = JsonObject()
        memory.put("backend", JsonString(""))
        root.put("memory", memory)
        @Expect(CliSettingManager.resolvedMemoryProvider(setting, root: Some(root)), "local")
    }

    @TestCase
    public func explicitTopLevelMemoryBackendWinsOverLegacyProvider(): Unit {
        var setting = CliSetting()
        setting.memory.backend = ""
        setting.memoryProvider = "qmd"
        let root = JsonObject()
        let memory = JsonObject()
        memory.put("backend", JsonString("sqlite-fts+local-file"))
        root.put("memory", memory)
        @Expect(
            CliSettingManager.resolvedMemoryProvider(setting, root: Some(root)),
            "sqlite-fts+local-file"
        )
    }

    @TestCase
    public func legacyMemoryProviderStillWorksWithoutTopLevelMemoryBlock(): Unit {
        var setting = CliSetting()
        setting.memory.backend = ""
        setting.memoryProvider = "qmd"
        @Expect(CliSettingManager.resolvedMemoryProvider(setting), "qmd")
    }

    @TestCase
    public func resolvedPrimaryModelForSavePrefersNormalizedConfigPrimary(): Unit {
        var setting = CliSetting()
        setting.model = "ark:qwen3.5-plus"
        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        let model = JsonObject()
        model.put("primary", JsonString("qwen/qwen3.6-plus"))
        defaults.put("model", model)
        agents.put("defaults", defaults)
        root.put("agents", agents)
        @Expect(
            CliSettingManager.resolvedPrimaryModelForSave(setting, root),
            "dashscope:qwen3.6-plus"
        )
    }

    @TestCase
    public func resolvedPrimaryModelForSaveDoesNotInjectHardcodedDefault(): Unit {
        let setting = CliSetting()
        @Expect(CliSettingManager.resolvedPrimaryModelForSave(setting, JsonObject()), "")
    }

    @TestCase
    public func agentsDefaultsImageModelIsLoadedSeparatelyFromPrimaryModel(): Unit {
        withMetisConfigTestHome("image-model-load") { _home =>
            let oldModel = CliConfig.modelOrEmpty()
            let oldImageModel = CliConfig.imageModelOrEmpty()
            let oldFallbacks = CliConfig.fallbackModels
            let oldImageFallbacks = CliConfig.imageFallbackModels
            let root = JsonObject()
            let agents = JsonObject()
            let defaults = JsonObject()
            let model = JsonObject()
            model.put("primary", JsonString("deepseek/deepseek-v4-pro"))
            defaults.put("model", model)
            let imageModel = JsonObject()
            imageModel.put("primary", JsonString("qwen/qwen-vl-max"))
            imageModel.put("fallbacks", JsonArray([JsonString("openai/gpt-4o")]))
            defaults.put("imageModel", imageModel)
            agents.put("defaults", defaults)
            root.put("agents", agents)
            MetisConfigManager.writeRoot(root)
            CliSettingManager.invalidate()
            MetisConfigManager.applyPersistedFieldsToCliConfig()

            @Expect(CliConfig.modelOrEmpty(), "deepseek:deepseek-v4-pro")
            @Expect(CliConfig.imageModelOrEmpty(), "dashscope:qwen-vl-max")
            @Expect(CliConfig.imageFallbackModels[0], "openai:gpt-4o")
            CliConfig.model = oldModel
            CliConfig.imageModel = oldImageModel
            CliConfig.fallbackModels = oldFallbacks
            CliConfig.imageFallbackModels = oldImageFallbacks
        }
    }

    @TestCase
    public func settingAssignmentDoesNotPersistWithoutExplicitPatch(): Unit {
        withMetisConfigTestHome("setting-assignment-no-save") { _home =>
            let root = JsonObject()
            let agents = JsonObject()
            let defaults = JsonObject()
            let model = JsonObject()
            model.put("primary", JsonString("qwen/qwen3.6-plus"))
            defaults.put("model", model)
            defaults.put("workspace", JsonString("/tmp/project"))
            agents.put("defaults", defaults)
            root.put("agents", agents)
            MetisConfigManager.writeRoot(root)

            var updated = CliSettingManager.setting
            updated.model = "openai:gpt-5"
            CliSettingManager.setting = updated

            let persistedPrimary = MetisConfigManager.rawConfig().getOrThrow()
                .get("agents").getOrThrow().asObject()
                .get("defaults").getOrThrow().asObject()
                .get("model").getOrThrow().asObject()
                .get("primary").getOrThrow().asString().getValue()
            @Expect(persistedPrimary, "qwen/qwen3.6-plus")
            @Expect(CliSettingManager.setting.model, "openai:gpt-5")

            CliSettingManager.invalidate()
            @Expect(CliSettingManager.setting.model, "dashscope:qwen3.6-plus")
        }
    }

    @TestCase
    public func gatewaySettingsReadKeepsAuthAndChannelFlagsWhenTelegramAllowFromHasNumber(): Unit {
        withMetisConfigTestHome("gateway-field-tolerant-read") { _home =>
            let root = JsonObject()
            let gateway = JsonObject()
            let auth = JsonObject()
            auth.put("mode", JsonString("token"))
            auth.put("token", JsonString("existing-token"))
            gateway.put("auth", auth)

            let telegram = JsonObject()
            telegram.put("enabled", JsonBool(true))
            telegram.put("allowFrom", JsonArray([JsonInt(8734062810)]))
            gateway.put("telegram", telegram)

            let qq = JsonObject()
            qq.put("enabled", JsonBool(true))
            gateway.put("qq", qq)
            root.put("gateway", gateway)
            MetisConfigManager.writeRoot(root)
            CliSettingManager.invalidate()

            let parsed = CliSettingManager.readGatewaySettings()
            @Expect(parsed.auth.token, "existing-token")
            @Expect(parsed.telegram.enabled, true)
            @Expect(parsed.telegram.allowFrom.size, 1)
            @Expect(parsed.telegram.allowFrom[0], "8734062810")
            @Expect(parsed.qq.enabled, true)
        }
    }

    @TestCase
    public func gatewaySettingsReadParsesTelegramTypedOpenClawParityConfigInTempHome(): Unit {
        withMetisConfigTestHome("telegram-typed-config-read") { _home =>
            let root = JsonObject()
            let gateway = JsonObject()
            let telegram = JsonObject()
            telegram.put("enabled", JsonBool(true))
            telegram.put("defaultAccount", JsonString("work"))
            let inlineButtons = JsonObject()
            inlineButtons.put("scope", JsonString("dm"))
            inlineButtons.put("allowlist", JsonArray([JsonString("tg:dm:8734062810")]))
            telegram.put("inlineButtons", inlineButtons)
            let execApprovals = JsonObject()
            execApprovals.put("enabled", JsonString("true"))
            execApprovals.put("approvers", JsonArray([JsonString("8734062810")]))
            execApprovals.put("agentFilter", JsonArray([JsonString("reviewer")]))
            execApprovals.put("sessionFilter", JsonArray([JsonString("telegram:direct")]))
            execApprovals.put("target", JsonString("both"))
            telegram.put("execApprovals", execApprovals)
            let errorPolicy = JsonObject()
            errorPolicy.put("policy", JsonString("once"))
            errorPolicy.put("cooldownMs", JsonInt(9876))
            errorPolicy.put("silentErrorReplies", JsonBool(true))
            telegram.put("errorPolicy", errorPolicy)
            let autoTopicLabel = JsonObject()
            autoTopicLabel.put("enabled", JsonBool(true))
            autoTopicLabel.put("strategy", JsonString("model"))
            autoTopicLabel.put("prompt", JsonString("label prompt"))
            telegram.put("autoTopicLabel", autoTopicLabel)
            gateway.put("telegram", telegram)
            root.put("gateway", gateway)
            MetisConfigManager.writeRoot(root)
            CliSettingManager.invalidate()

            let parsed = CliSettingManager.readGatewaySettings()
            @Expect(parsed.telegram.enabled, true)
            @Expect(parsed.telegram.defaultAccount, "work")
            @Expect(parsed.telegram.inlineButtons.scope, "dm")
            @Expect(parsed.telegram.inlineButtons.allowlist[0], "tg:dm:8734062810")
            @Expect(parsed.telegram.execApprovals.enabled, "true")
            @Expect(parsed.telegram.execApprovals.approvers[0], "8734062810")
            @Expect(parsed.telegram.execApprovals.agentFilter[0], "reviewer")
            @Expect(parsed.telegram.execApprovals.sessionFilter[0], "telegram:direct")
            @Expect(parsed.telegram.execApprovals.target, "both")
            @Expect(parsed.telegram.errorPolicy.policy, "once")
            @Expect(parsed.telegram.errorPolicy.cooldownMs, 9876)
            @Expect(parsed.telegram.errorPolicy.silentErrorReplies, true)
            @Expect(parsed.telegram.autoTopicLabel.enabled, true)
            @Expect(parsed.telegram.autoTopicLabel.strategy, "model")
            @Expect(parsed.telegram.autoTopicLabel.prompt, "label prompt")
        }
    }
}
