package metis.core.config

import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

@Test
public class CliImageModelConfigTest {
    private func rootWithModelAndImageModel(): JsonObject {
        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        let model = JsonObject()
        model.put("primary", JsonString("deepseek/deepseek-v4-pro"))
        let imageModel = JsonObject()
        imageModel.put("primary", JsonString("qwen/qwen-vl-max"))
        imageModel.put("fallbacks", JsonArray([JsonString("openai/gpt-4o")]))
        defaults.put("model", model)
        defaults.put("imageModel", imageModel)
        agents.put("defaults", defaults)
        root.put("agents", agents)
        root
    }

    @TestCase
    public func agentsDefaultsImageModelMaterializesWithoutChangingChatPrimary(): Unit {
        let oldModel = CliConfig.modelOrEmpty()
        let oldFallbacks = CliConfig.fallbackModels
        let oldImageModel = CliConfig.imageModelOrEmpty()
        let oldImageFallbacks = CliConfig.imageFallbackModels
        withMetisConfigTestHome("image-model-materializes") { _home =>
            try {
                MetisConfigManager.writeRoot(this.rootWithModelAndImageModel())
                CliSettingManager.invalidate()

                CliSettingManager.applyPersistedFieldsToCliConfig()

                @Expect(CliConfig.modelOrEmpty(), "deepseek:deepseek-v4-pro")
                @Expect(CliConfig.imageModelOrEmpty(), "dashscope:qwen-vl-max")
                @Expect(CliConfig.imageFallbackModels.size, 1)
                @Expect(CliConfig.imageFallbackModels[0], "openai:gpt-4o")
            } finally {
                if (oldModel.isEmpty()) {
                    CliConfig.clearPrimaryModelForTest()
                } else {
                    CliConfig.model = oldModel
                }
                CliConfig.fallbackModels = oldFallbacks
                if (oldImageModel.isEmpty()) {
                    CliConfig.clearImageModelForTest()
                } else {
                    CliConfig.imageModel = oldImageModel
                }
                CliConfig.imageFallbackModels = oldImageFallbacks
            }
        }
    }

    @TestCase
    public func missingImageModelClearsRuntimeImageModelFields(): Unit {
        let oldModel = CliConfig.modelOrEmpty()
        let oldFallbacks = CliConfig.fallbackModels
        let oldImageModel = CliConfig.imageModelOrEmpty()
        let oldImageFallbacks = CliConfig.imageFallbackModels
        withMetisConfigTestHome("missing-image-model-clears") { _home =>
            try {
                CliConfig.imageModel = "dashscope:qwen-vl-max"
                CliConfig.imageFallbackModels = ["openai:gpt-4o"]

                let root = JsonObject()
                let agents = JsonObject()
                let defaults = JsonObject()
                let model = JsonObject()
                model.put("primary", JsonString("deepseek/deepseek-v4-pro"))
                defaults.put("model", model)
                agents.put("defaults", defaults)
                root.put("agents", agents)
                MetisConfigManager.writeRoot(root)
                CliSettingManager.invalidate()

                CliSettingManager.applyPersistedFieldsToCliConfig()

                @Expect(CliConfig.modelOrEmpty(), "deepseek:deepseek-v4-pro")
                @Expect(CliConfig.imageModelOrEmpty(), "")
                @Expect(CliConfig.imageFallbackModels.size, 0)
            } finally {
                if (oldModel.isEmpty()) {
                    CliConfig.clearPrimaryModelForTest()
                } else {
                    CliConfig.model = oldModel
                }
                CliConfig.fallbackModels = oldFallbacks
                if (oldImageModel.isEmpty()) {
                    CliConfig.clearImageModelForTest()
                } else {
                    CliConfig.imageModel = oldImageModel
                }
                CliConfig.imageFallbackModels = oldImageFallbacks
            }
        }
    }
}
