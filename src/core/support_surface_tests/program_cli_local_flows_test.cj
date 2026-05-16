package metis.core.support_surface_tests

import metis.core.config.{CliSettingManager, MetisConfigManager}
import metis.program_support.*

import std.env.setVariable
import std.unittest.testmacro.*
import std.collection.ArrayList
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

@Test
public class CliLocalFlowsTest {
    @BeforeAll
    public func isolateMetisHome(): Unit {
        setVariable("METIS_HOME", "/tmp/metis-program-cli-local-flows-test-home")
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }

    @TestCase
    public func localCommandSummaryRendersHumanTextWithoutRawJson(): Unit {
        let steps = ArrayList<JsonValue>()
        steps.add(JsonString("metis models current"))
        steps.add(JsonString("metis models providers"))

        let obj = JsonObject()
        obj.put("kind", JsonString("models"))
        obj.put("subcommand", JsonString("status"))
        obj.put("currentModel", JsonString("ark:kimi-k2-250905"))
        obj.put("provider", JsonString("ark"))
        obj.put("nextSteps", JsonArray(steps))

        let rendered = programSupportRenderLocalCommandSummary(obj)

        @Expect(rendered.contains("Metis models status"), true)
        @Expect(rendered.contains("Current model: ark:kimi-k2-250905"), true)
        @Expect(rendered.contains("Next steps:"), true)
        @Expect(rendered.contains("{"), false)
        @Expect(rendered.contains("\"kind\""), false)
        @Expect(rendered.contains("Machine output: rerun with --json."), true)
    }

    @TestCase
    public func localCommandSummaryHidesNestedCatalogDetails(): Unit {
        let providers = ArrayList<JsonValue>()
        providers.add(JsonString("ark"))

        let obj = JsonObject()
        obj.put("kind", JsonString("models"))
        obj.put("subcommand", JsonString("providers"))
        obj.put("providers", JsonArray(providers))

        let rendered = programSupportRenderLocalCommandSummary(obj)

        @Expect(rendered.contains("Metis models providers"), true)
        @Expect(rendered.contains("Catalog details: available with --json"), true)
    }

    @TestCase
    public func modelsStatusMentionsIndependentImageModel(): Unit {
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
        root.put("gateway", JsonObject())
        MetisConfigManager.writeRoot(root)
        CliSettingManager.applyPersistedFieldsToCliConfig()

        let rendered = programSupportRenderModelsStatus()

        @Expect(rendered.contains("Image primary: qwen:qwen-vl-max"), true)
        @Expect(rendered.contains("Image fallbacks: openai:gpt-4o"), true)
        @Expect(rendered.contains("independent from the main chat model"), true)
    }
}
