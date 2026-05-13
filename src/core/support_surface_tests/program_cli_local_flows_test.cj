package metis.core.support_surface_tests

import metis.program_support.*

import std.unittest.testmacro.*
import std.collection.ArrayList
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

@Test
public class CliLocalFlowsTest {
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
}
