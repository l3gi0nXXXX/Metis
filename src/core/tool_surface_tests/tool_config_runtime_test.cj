package metis.core.tool_surface_tests

import metis.core.tools.*

import metis.core.tools.cj_utils.{context7ApiKey, hasContext7ApiKey}

import std.env.setVariable
import std.unittest.testmacro.*

@Test
public class ToolConfigRuntimeTest {
    @TestCase
    public func context7HelpersReadEnvironmentFallback(): Unit {
        setVariable("CONTEXT7_API_KEY", "ctx-env")
        @Expect(context7ApiKey(), "ctx-env")
        @Expect(hasContext7ApiKey(), true)
    }
}
