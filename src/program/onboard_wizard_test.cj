package metis.program

import std.env.{getVariable, setVariable}
import std.fs.{Directory, Path, remove}
import std.unittest.testmacro.*

import metis.core.config.MetisPaths

import stdx.encoding.json.{JsonObject, JsonString}

@Test
public class OnboardWizardTest {
    @TestCase
    public func workspacePromptStateSeparatesCurrentDirectoryFromConfiguredDefault(): Unit {
        let testHome = "/tmp/metis-phase6-onboard-workspace-state"
        try {
            remove(Path(testHome), recursive: true)
        } catch (_: Exception) {
            ()
        }
        Directory.create(testHome, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)

        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        defaults.put("workspace", JsonString("/tmp/configured-workspace"))
        agents.put("defaults", defaults)
        root.put("agents", agents)

        let expectedCurrent = MetisPaths.workspaceRoot().toString()
        let (currentDirectory, configuredWorkspace, effectiveWorkspace, showConfiguredOption) = onboardWorkspacePromptState(root)
        @Expect(currentDirectory, expectedCurrent)
        @Expect(configuredWorkspace, "/tmp/configured-workspace")
        @Expect(effectiveWorkspace, "/tmp/configured-workspace")
        @Expect(showConfiguredOption, true)

        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
    }

    @TestCase
    public func workspacePromptStateFallsBackToCurrentDirectoryWhenUnset(): Unit {
        let root = JsonObject()
        let expectedCurrent = MetisPaths.workspaceRoot().toString()
        let (currentDirectory, configuredWorkspace, effectiveWorkspace, showConfiguredOption) = onboardWorkspacePromptState(root)
        @Expect(currentDirectory, expectedCurrent)
        @Expect(configuredWorkspace, "")
        @Expect(effectiveWorkspace, expectedCurrent)
        @Expect(showConfiguredOption, false)
    }
}
