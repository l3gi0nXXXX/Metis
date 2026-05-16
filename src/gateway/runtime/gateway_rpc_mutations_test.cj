package metis.gateway.runtime

import metis.core.config.{CliSettingManager, MetisConfigManager}
import std.env.setVariable
import stdx.encoding.json.{JsonArray, JsonString}

import std.unittest.testmacro.*
import stdx.encoding.json.JsonObject

private func gatewayRpcMutationsTestConfigRoot(): JsonObject {
    let root = JsonObject()
    let agents = JsonObject()
    let defaults = JsonObject()
    defaults.put("workspace", JsonString(""))
    agents.put("defaults", defaults)
    root.put("agents", agents)
    root.put("gateway", JsonObject())
    root.put("session", JsonObject())
    root.put("skills", JsonObject())
    root.put("tools", JsonObject())
    root.put("models", JsonObject())
    root.put("auth", JsonObject())
    root.put("channels", JsonObject())
    root.put("plugins", JsonObject())
    root.put("wizard", JsonObject())
    root.put("meta", JsonObject())
    root
}

@Test
public class GatewayRpcMutationsTest {
    @BeforeAll
    public func isolateMetisHome(): Unit {
        setVariable("METIS_HOME", "/tmp/metis-gateway-rpc-mutations-test-home")
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }

    @TestCase
    public func configPatchStillSupportsPointPathUpdates(): Unit {
        let originalRoot = MetisConfigManager.rawConfig() ?? JsonObject()
        MetisConfigManager.writeRoot(gatewayRpcMutationsTestConfigRoot())
        CliSettingManager.applyPersistedFieldsToCliConfig()
        let original = CliSettingManager.readGatewaySettings()
        try {
            let result = applyGatewayConfigPatch(" gateway.controlUi.enabled ", "false")
            @Expect(result[0], true)
            @Expect(result[1].contains("gateway.controlUi.enabled updated"), true)
            @Expect(CliSettingManager.readGatewaySettings().controlUi.enabled, false)
        } finally {
            let _ = original
            MetisConfigManager.writeRoot(originalRoot)
            CliSettingManager.applyPersistedFieldsToCliConfig()
        }
    }

    @TestCase
    public func configPatchSupportsObjectMergeWithoutExplicitPath(): Unit {
        MetisConfigManager.initializeIfMissing()
        let originalRoot = match (MetisConfigManager.rawConfig()) {
            case Some(root) => root
            case None => JsonObject()
        }
        try {
            let result = applyGatewayConfigPatch(
                "",
                "{\"plugins\":{\"entries\":{\"memory-core\":{\"config\":{\"dreaming\":{\"enabled\":false}}}}}}"
            )
            @Expect(result[0], true)
            @Expect(result[1].contains("object patch merged"), true)

            let updatedRoot = MetisConfigManager.rawConfig().getOrThrow()
            let plugins = updatedRoot.get("plugins").getOrThrow().asObject()
            let entries = plugins.get("entries").getOrThrow().asObject()
            let memoryCore = entries.get("memory-core").getOrThrow().asObject()
            let config = memoryCore.get("config").getOrThrow().asObject()
            let dreaming = config.get("dreaming").getOrThrow().asObject()
            @Expect(dreaming.get("enabled").getOrThrow().asBool().getValue(), false)
        } finally {
            MetisConfigManager.writeRoot(originalRoot)
            CliSettingManager.applyPersistedFieldsToCliConfig()
        }
    }

    @TestCase
    public func configPatchSupportsTypedTelegramPointPathUpdates(): Unit {
        let originalRoot = MetisConfigManager.rawConfig() ?? JsonObject()
        MetisConfigManager.writeRoot(gatewayRpcMutationsTestConfigRoot())
        CliSettingManager.applyPersistedFieldsToCliConfig()
        let original = CliSettingManager.readGatewaySettings()
        try {
            let enabledResult = applyGatewayConfigPatch("gateway.telegram.enabled", "true")
            @Expect(enabledResult[0], true)
            @Expect(enabledResult[1].contains("gateway.telegram.enabled updated"), true)

            let tokenResult = applyGatewayConfigPatch("gateway.telegram.botToken", "telegram-token")
            @Expect(tokenResult[0], true)
            @Expect(tokenResult[1].contains("gateway.telegram.botToken updated"), true)

            let webhookResult = applyGatewayConfigPatch("gateway.telegram.webhookUrl", "https://example.test/telegram-webhook")
            @Expect(webhookResult[0], true)
            @Expect(webhookResult[1].contains("gateway.telegram.webhookUrl updated"), true)

            let updated = CliSettingManager.readGatewaySettings()
            @Expect(updated.telegram.enabled, true)
            @Expect(updated.telegram.botToken, "telegram-token")
            @Expect(updated.telegram.webhookUrl, "https://example.test/telegram-webhook")

            let telegram = updated.toJsonValue().asObject().get("telegram").getOrThrow().asObject()
            @Expect(telegram.get("botToken").getOrThrow().asString().getValue(), "telegram-token")
            @Expect(telegram.get("webhookUrl").getOrThrow().asString().getValue(), "https://example.test/telegram-webhook")
        } finally {
            let _ = original
            MetisConfigManager.writeRoot(originalRoot)
            CliSettingManager.applyPersistedFieldsToCliConfig()
        }
    }

    @TestCase
    public func configPatchSupportsImageUnderstandingAdminPaths(): Unit {
        let originalRoot = MetisConfigManager.rawConfig() ?? JsonObject()
        MetisConfigManager.writeRoot(gatewayRpcMutationsTestConfigRoot())
        CliSettingManager.applyPersistedFieldsToCliConfig()
        try {
            let imageModelResult = applyGatewayConfigPatch("agents.defaults.imageModel.primary", "qwen/qwen-vl-max")
            @Expect(imageModelResult[0], true)
            @Expect(imageModelResult[1].contains("agents.defaults.imageModel.primary updated"), true)

            let mediaImageResult = applyGatewayConfigPatch(
                "gateway.media.image",
                "{\"enabled\":true,\"models\":[{\"provider\":\"shared-qwen\",\"model\":\"qwen-vl-max\",\"capabilities\":[\"image\"]}]}"
            )
            @Expect(mediaImageResult[0], true)
            @Expect(mediaImageResult[1].contains("gateway.media.image updated"), true)

            let updatedRoot = MetisConfigManager.rawConfig().getOrThrow()
            let defaults = updatedRoot.get("agents").getOrThrow().asObject().get("defaults").getOrThrow().asObject()
            let imageModel = defaults.get("imageModel").getOrThrow().asObject()
            @Expect(imageModel.get("primary").getOrThrow().asString().getValue(), "qwen/qwen-vl-max")

            let gateway = updatedRoot.get("gateway").getOrThrow().asObject()
            let media = gateway.get("media").getOrThrow().asObject()
            let image = media.get("image").getOrThrow().asObject()
            let models = image.get("models").getOrThrow().asArray()
            @Expect(models.size(), 1)
            @Expect(models[0].asObject().get("provider").getOrThrow().asString().getValue(), "shared-qwen")
        } finally {
            MetisConfigManager.writeRoot(originalRoot)
            CliSettingManager.applyPersistedFieldsToCliConfig()
        }
    }

    @TestCase
    public func configPatchSupportsWholeRootControlUiSave(): Unit {
        let originalRoot = MetisConfigManager.rawConfig() ?? JsonObject()
        MetisConfigManager.writeRoot(gatewayRpcMutationsTestConfigRoot())
        CliSettingManager.applyPersistedFieldsToCliConfig()
        try {
            let replacement = gatewayRpcMutationsTestConfigRoot()
            let agents = replacement.get("agents").getOrThrow().asObject()
            let defaults = agents.get("defaults").getOrThrow().asObject()
            let imageModel = JsonObject()
            imageModel.put("primary", JsonString("openai/gpt-4o"))
            imageModel.put("fallbacks", JsonArray([JsonString("qwen/qwen-vl-max")]))
            defaults.put("imageModel", imageModel)

            let result = applyGatewayConfigPatch("", replacement.toJsonString())
            @Expect(result[0], true)
            @Expect(result[1].contains("config root replaced"), true)

            let persisted = MetisConfigManager.rawConfig().getOrThrow()
            let persistedDefaults = persisted.get("agents").getOrThrow().asObject().get("defaults").getOrThrow().asObject()
            let persistedImageModel = persistedDefaults.get("imageModel").getOrThrow().asObject()
            @Expect(persistedImageModel.get("primary").getOrThrow().asString().getValue(), "openai/gpt-4o")
        } finally {
            MetisConfigManager.writeRoot(originalRoot)
            CliSettingManager.applyPersistedFieldsToCliConfig()
        }
    }
}
