package metis.core.support_surface_tests

import metis.core.config.CliConfig
import metis.core.memory.DreamingPhaseRuntime

import std.env.{getVariable, setVariable}
import std.fs.{Path, remove}
import std.unittest.testmacro.*

private func dreamingPhaseRestoreEnv(oldHome: Option<String>, oldWorkspace: String): Unit {
    match (oldHome) {
        case Some(value) => setVariable("METIS_HOME", value)
        case None => setVariable("METIS_HOME", "")
    }
    CliConfig.workspaceDirOverride = oldWorkspace
    CliConfig.invalidatePathCache()
}

@Test
public class DreamingPhaseRuntimeTest {
    @TestCase
    public func statusTextIsHumanReadableAndJsonStaysExplicit(): Unit {
        let oldHome = getVariable("METIS_HOME")
        let oldWorkspace = CliConfig.workspaceDirOverride
        let testHome = "/tmp/metis-dreaming-phase-runtime-test-home"
        try { remove(Path(testHome), recursive: true) } catch (_: Exception) { () }
        setVariable("METIS_HOME", testHome)
        CliConfig.workspaceDirOverride = "/tmp/metis-dreaming-phase-runtime-test-workspace"
        CliConfig.invalidatePathCache()
        try {
            let text = DreamingPhaseRuntime.buildStatusText()
            @Expect(text.contains("Memory dreaming"), true)
            @Expect(text.contains("Phases:"), true)
            @Expect(text.contains("\"phases\""), false)
            @Expect(text.startsWith("{"), false)
            let json = DreamingPhaseRuntime.buildStatusJson()
            @Expect(json.contains("\"phases\""), true)
            @Expect(json.startsWith("{"), true)
        } finally {
            try { remove(Path(testHome), recursive: true) } catch (_: Exception) { () }
            dreamingPhaseRestoreEnv(oldHome, oldWorkspace)
        }
    }
}
