package metis.program

import std.env.setVariable
import std.fs.Directory
import std.unittest.testmacro.*

import metis.core.config.{CliConfig, MetisConfigManager}

import stdx.encoding.json.{JsonObject, JsonString}

@Test
public class ModelConfigViewTest {
    @TestCase
    public func providerCatalogExposesConfigPathsInsteadOfEnvNames(): Unit {
        let rows = cliBuildProviderCatalog()
        var matched = false
        for (item in rows.getItems()) {
            let row = item.asObject()
            let provider = row.get("provider").getOrThrow().asString().getValue()
            if (provider == "qwen") {
                matched = true
                @Expect(
                    row.get("apiKeyConfigPath").getOrThrow().asString().getValue(),
                    "models.providers.qwen.apiKey"
                )
                @Expect(
                    row.get("baseUrlConfigPath").getOrThrow().asString().getValue(),
                    "models.providers.qwen.baseUrl"
                )
                @Expect(row.get("apiKeyEnv").isSome(), false)
                @Expect(row.get("baseUrlEnv").isSome(), false)
            }
        }
        @Expect(matched, true)
    }

    /*
    @TestCase
    public func currentModelViewUsesCanonicalConfigProviderForLegacyRuntimeAliases(): Unit {
        let testHome = "/tmp/metis-phase4-current-model-view"
        Directory.create(testHome, recursive: true)
        setVariable("METIS_HOME", testHome)
        MetisConfigManager.invalidate()

        let root = JsonObject()
        let models = JsonObject()
        let providers = JsonObject()
        let volcengine = JsonObject()
        volcengine.put("apiKey", JsonString("vk-test"))
        volcengine.put("baseUrl", JsonString("https://ark.cn-beijing.volces.com/api/coding/v3"))
        providers.put("volcengine", volcengine)
        models.put("providers", providers)
        root.put("models", models)
        MetisConfigManager.writeRoot(root)

        let oldModel = try { CliConfig.model } catch (_: Exception) { "" }
        CliConfig.model = "ark:kimi-k2-250905"

        let current = cliBuildCurrentModelConfigView()
        @Expect(current.get("provider").getOrThrow().asString().getValue(), "ark")
        @Expect(current.get("configProvider").getOrThrow().asString().getValue(), "volcengine")
        @Expect(current.get("apiKeyConfigPath").getOrThrow().asString().getValue(), "models.providers.volcengine.apiKey")
        @Expect(current.get("baseUrlConfigPath").getOrThrow().asString().getValue(), "models.providers.volcengine.baseUrl")
        @Expect(current.get("configured").getOrThrow().asBool().getValue(), true)

        CliConfig.model = oldModel
    }
    */
}
