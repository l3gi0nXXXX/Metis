package metis.core.model

import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

@Test
public class ModelCapabilityResolverTest {
    @TestCase
    public func knownDeepseekTextModelDoesNotSupportImageInput(): Unit {
        let decision = resolveModelImageCapability("deepseek/deepseek-v4-pro")

        @Expect(decision.normalizedRef, "deepseek:deepseek-v4-pro")
        @Expect(modelVisionSupportToString(decision.vision), "unsupported")
        @Expect(decision.source, "built-in-deny")
    }

    @TestCase
    public func knownQwenVisionModelSupportsSlashAndColonRefs(): Unit {
        let slashDecision = resolveModelImageCapability("qwen/qwen-vl-max")
        let colonDecision = resolveModelImageCapability("dashscope:qwen-vl-max")

        @Expect(slashDecision.normalizedRef, "dashscope:qwen-vl-max")
        @Expect(modelVisionSupportToString(slashDecision.vision), "supported")
        @Expect(modelVisionSupportToString(colonDecision.vision), "supported")
    }

    @TestCase
    public func explicitConfigCapabilitiesOverrideUnknownProviderHeuristic(): Unit {
        let entry = JsonObject()
        entry.put("provider", JsonString("custom"))
        entry.put("model", JsonString("vision-x"))
        entry.put("capabilities", JsonArray([JsonString("image")]))

        let decision = resolveModelImageCapabilityFromEntry(entry)

        @Expect(decision.normalizedRef, "custom:vision-x")
        @Expect(modelVisionSupportToString(decision.vision), "supported")
        @Expect(decision.source, "explicit-config")
    }

    @TestCase
    public func unknownModelWithoutExplicitImageInputIsUnsupported(): Unit {
        let entry = JsonObject()
        entry.put("provider", JsonString("custom"))
        entry.put("model", JsonString("text-x"))

        let decision = resolveModelImageCapabilityFromEntry(entry)

        @Expect(decision.normalizedRef, "custom:text-x")
        @Expect(modelVisionSupportToString(decision.vision), "unknown")
        @Expect(decision.reason.contains("capability is unknown"), true)
    }
}
