package metis.core.support_surface_tests

import metis.program_support.*

import metis.core.config.MetisPaths
import std.unittest.testmacro.*

import stdx.encoding.json.{JsonObject, JsonString}

@Test
public class OnboardWizardTest {
    @TestCase
    public func workspacePromptStateSeparatesCurrentDirectoryFromConfiguredDefault(): Unit {
        withProgramSupportConfigTestHome("onboard-workspace", { _home =>
            let root = JsonObject()
            let agents = JsonObject()
            let defaults = JsonObject()
            defaults.put("workspace", JsonString("/tmp/configured-workspace"))
            agents.put("defaults", defaults)
            root.put("agents", agents)

            let expectedCurrent = MetisPaths.workspaceRoot().toString()
            let (currentDirectory, configuredWorkspace, effectiveWorkspace, showConfiguredOption) = programSupportOnboardWorkspacePromptState(root)
            @Expect(currentDirectory, expectedCurrent)
            @Expect(configuredWorkspace, "/tmp/configured-workspace")
            @Expect(effectiveWorkspace, "/tmp/configured-workspace")
            @Expect(showConfiguredOption, true)
        })
    }

    @TestCase
    public func workspacePromptStateFallsBackToCurrentDirectoryWhenUnset(): Unit {
        let root = JsonObject()
        let expectedCurrent = MetisPaths.workspaceRoot().toString()
        let (currentDirectory, configuredWorkspace, effectiveWorkspace, showConfiguredOption) = programSupportOnboardWorkspacePromptState(root)
        @Expect(currentDirectory, expectedCurrent)
        @Expect(configuredWorkspace, "")
        @Expect(effectiveWorkspace, expectedCurrent)
        @Expect(showConfiguredOption, false)
    }
}
